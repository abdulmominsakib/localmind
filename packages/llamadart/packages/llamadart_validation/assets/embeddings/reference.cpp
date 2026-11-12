#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <vector>
#include <string>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <stdexcept>
static void check(bool ok) { if (!ok) throw std::runtime_error("reference failed"); }
int main(int argc, char**argv) {
 check(argc==6); bool metal=std::string(argv[3])=="metal";
 llama_backend_init(); auto mp=llama_model_default_params(); mp.n_gpu_layers=metal?-1:0;
 ggml_backend_dev_t cpu_devices[]={ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU),nullptr};
 if(!metal)mp.devices=cpu_devices;
 auto*m=llama_model_load_from_file(argv[1],mp); check(m);
 auto cp=llama_context_default_params(); cp.n_ctx=cp.n_batch=cp.n_ubatch=2048;
 cp.n_threads=cp.n_threads_batch=4; cp.embeddings=true;
 if(!metal) {cp.offload_kqv=false;cp.op_offload=false;cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_DISABLED;}
 auto*c=llama_init_from_model(m,cp); check(c);
 auto pp=mtmd_context_params_default(); pp.use_gpu=metal; pp.n_threads=4;
 auto*p=mtmd_init_from_file(argv[2],m,pp); check(p);
 std::string root=argv[5];
 auto*checker=mtmd_helper_bitmap_init_from_file(p,(root+"/checker.png").c_str(),false,mtmd_helper_init_opt_default()).bitmap; check(checker);
 auto*tone=mtmd_helper_bitmap_init_from_file(p,(root+"/tone.wav").c_str(),false,mtmd_helper_init_opt_default()).bitmap; check(tone);
 std::string marker=mtmd_default_marker();
 std::vector<std::string> prompts={"The Eiffel Tower is in Paris.",marker,marker,"first "+marker+" between "+marker+" last", "first "+marker+" between "+marker+" last"};
 std::vector<std::vector<const mtmd_bitmap*>> inputs={{},{checker},{tone},{checker,tone},{tone,checker}};
 std::ofstream out(argv[4]); out<<std::setprecision(17)<<"[";
 for(int q=0;q<5;q++) {
  if(auto mem=llama_get_memory(c))llama_memory_clear(mem,true);
  if(q==0) {
   auto*v=llama_model_get_vocab(m);std::vector<llama_token>t(128);
   int n=llama_tokenize(v,prompts[q].data(),prompts[q].size(),t.data(),t.size(),true,true);check(n>0);
   auto b=llama_batch_init(n,0,1);b.n_tokens=n;
   for(int i=0;i<n;i++){b.token[i]=t[i];b.pos[i]=i;b.n_seq_id[i]=1;b.seq_id[i][0]=0;b.logits[i]=1;}
   check(llama_decode(c,b)==0);llama_batch_free(b);
  } else {
   auto*chunks=mtmd_input_chunks_init();mtmd_input_text text{prompts[q].data(),prompts[q].size(),true,true};
   check(mtmd_tokenize(p,chunks,&text,inputs[q].data(),inputs[q].size())==0);
   auto*b=llama_batch_ext_init(c);check(b);std::vector<std::vector<float>>copies;
   int width=llama_model_n_embd_inp(m);llama_pos pos=0;
   for(size_t k=0;k<mtmd_input_chunks_size(chunks);k++) {
    auto*chunk=mtmd_input_chunks_get(chunks,k);size_t n=mtmd_input_chunk_get_n_tokens(chunk);
    const llama_token*t=nullptr;const float*e=nullptr;
    if(mtmd_input_chunk_get_type(chunk)==MTMD_INPUT_CHUNK_TYPE_TEXT)t=mtmd_input_chunk_get_tokens_text(chunk,&n);
    else {check(mtmd_encode_chunk(p,chunk)==0);auto*output=mtmd_get_output_embd(p);check(output);copies.emplace_back(output,output+n*width);e=copies.back().data();}
    check(pos+n<=llama_n_ubatch(c));
    for(size_t i=0;i<n;i++,pos++) {int idx=t?llama_batch_ext_add_token(b,0,t[i]):llama_batch_ext_add_embd(b,0,{e+i*width,1,size_t(width)});
     check(idx>=0);check(llama_batch_ext_set_pos(b,idx,&pos));check(llama_batch_ext_set_output_embd(b,idx,true));}
   }
   check(llama_process(c,LLAMA_PROCESS_TYPE_DECODE,b)==0);llama_batch_ext_free(b);mtmd_input_chunks_free(chunks);
  }
  auto*e=llama_get_embeddings_seq(c,0);check(e);int width=llama_model_n_embd_out(m);check(width==768);double norm=0;
  for(int j=0;j<width;j++)norm+=double(e[j])*e[j];norm=std::sqrt(norm);
  if(q)out<<",";out<<"[";for(int j=0;j<width;j++){if(j)out<<",";out<<double(e[j])/norm;}out<<"]";
 }
 out<<"]\n";out.close();mtmd_bitmap_free(checker);mtmd_bitmap_free(tone);
 mtmd_free(p);llama_free(c);llama_model_free(m);llama_backend_free();
}
