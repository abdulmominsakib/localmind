"""Model-free ABI/configuration controls for the actual S24 native child source."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).with_name('main.cpp')
FIXTURE = r'''
#include <cstdlib>
#include <cstring>
#include <string>
static bool context=false, threads=false, benchmark=false, speculation=false;
static std::string backend, answer;
extern "C" {
const char* litert_lm_get_last_error_message(){return "Android GPU safety restriction: vendor=20803 device=1124406273 driver=2150604839 maxStorageBufferRange=134217728 fixture 555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4";}
int litert_lm_get_api_version(int*a,int*b,int*c){*a=std::getenv("WRONG_ABI")?2:1;*b=0;*c=0;return 0;}
int litert_lm_set_min_log_level(int level){return level;}
int litert_lm_engine_settings_create(const char*,const char*b,const char*,const char*,void**o){backend=b;*o=(void*)1;return 0;}
int litert_lm_engine_settings_set_num_threads(void*,int v){threads=v==4;return !threads;}
int litert_lm_engine_settings_set_max_num_tokens(void*,int v){context=v==1024;return !context;}
int litert_lm_engine_settings_set_cache_dir(void*,const char*){return 0;}
int litert_lm_engine_settings_enable_benchmark(void*){benchmark=true;return 0;}
int litert_lm_speculative_decoding_config_set_mode(void*,int v){speculation=v==0;return !speculation;}
int litert_lm_engine_settings_set_speculative_decoding_config(void*,void*){return 0;}
int litert_lm_engine_create(void*,void**o){if(std::getenv("GUARD")){*o=nullptr;return 9;}if(!context||!threads||!benchmark||!speculation)return 8;*o=(void*)2;return 0;}
#define CREATE(name) int name(void**o){*o=(void*)3;return 0;}
#define DELETE(name) void name(void*){}
CREATE(litert_lm_speculative_decoding_config_create)
CREATE(litert_lm_session_config_create)
CREATE(litert_lm_conversation_config_create)
CREATE(litert_lm_thinking_config_create)
CREATE(litert_lm_conversation_optional_args_create)
DELETE(litert_lm_speculative_decoding_config_delete)
DELETE(litert_lm_engine_settings_delete)
DELETE(litert_lm_engine_delete)
DELETE(litert_lm_sampler_params_delete)
DELETE(litert_lm_session_config_delete)
DELETE(litert_lm_conversation_config_delete)
DELETE(litert_lm_thinking_config_delete)
DELETE(litert_lm_conversation_delete)
DELETE(litert_lm_conversation_optional_args_delete)
DELETE(litert_lm_json_response_delete)
DELETE(litert_lm_benchmark_info_delete)
int litert_lm_sampler_params_create(int t,void**o){*o=(void*)3;return t==2?0:1;}
int litert_lm_sampler_params_set_top_k(void*,int v){return v==1?0:1;}
int litert_lm_sampler_params_set_top_p(void*,float v){return v==0.9f?0:1;}
int litert_lm_sampler_params_set_temperature(void*,float v){return v==0?0:1;}
int litert_lm_sampler_params_set_seed(void*,int v){return v==1?0:1;}
int litert_lm_session_config_set_sampler_params(void*,void*){return 0;}
int litert_lm_session_config_set_max_output_tokens(void*,int v){return v==32?0:1;}
int litert_lm_conversation_config_set_session_config(void*,void*){return 0;}
int litert_lm_thinking_config_set_enable_thinking(void*,bool v){return v?1:0;}
int litert_lm_conversation_config_set_thinking_config(void*,void*){return 0;}
int litert_lm_conversation_config_set_prompt_template(void*,const char*v){return std::strcmp(v,"fixture template");}
int litert_lm_conversation_config_set_extra_context(void*,const char*v){return std::strcmp(v,"{\"enable_thinking\":false}");}
int litert_lm_conversation_create(void*,void*,void**o){*o=(void*)4;return 0;}
int litert_lm_conversation_optional_args_set_max_output_tokens(void*,int v){return v==32?0:1;}
int litert_lm_conversation_send_message(void*,const char*m,const char*,void*,void**o){
 if(std::strstr(m,"Reply with one short sentence saying hello."))answer="{\"content\":[{\"type\":\"text\",\"text\":\"Hello!\"}]}";
 else if(std::strstr(m,"What is 3 + 4? Reply with only the number."))answer="{\"content\":[{\"type\":\"text\",\"text\":\"7\"}]}";
 else return 7;
 *o=(void*)5;return 0;}
int litert_lm_json_response_get_string(void*,const char**o){*o=std::getenv("NULL_JSON")?nullptr:answer.c_str();return 0;}
int litert_lm_conversation_get_benchmark_info(void*,void**o){*o=(void*)6;return 0;}
int litert_lm_benchmark_info_get_prefill_token_count_at(void*,size_t index,size_t*o){*o=12;return index==0?0:1;}
int litert_lm_benchmark_info_get_decode_token_count_at(void*,size_t index,size_t*o){*o=3;return index==0?0:1;}
}
'''

class ChildSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='s24-child-model-free-')
        cls.root = Path(cls.temp.name)
        compiler = shutil.which('clang++') or shutil.which('c++')
        if not compiler:
            raise unittest.SkipTest('C++17 compiler unavailable')
        cls.child = cls.root / 'child'
        subprocess.run([compiler, '-std=c++17', '-O2', '-Wall', '-Wextra', str(SOURCE), '-o', str(cls.child)], check=True)
        (cls.root / 'fixture.cpp').write_text(FIXTURE)
        cls.runtime = cls.root / 'fixture.dylib'
        subprocess.run([compiler, '-std=c++17', '-shared', '-fPIC', str(cls.root / 'fixture.cpp'), '-o', str(cls.runtime)], check=True)
        cls.template = cls.root / 'template.jinja'
        cls.template.write_text('fixture template')

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_child(self, mode='cpu', **environment):
        process = subprocess.run([str(self.child), mode, str(self.runtime), 'no-model-loaded', str(self.root),
            str(self.template), 'a'*64, 's24.native.gpu-corrected'], capture_output=True, timeout=5,
            env={**os.environ, **environment})
        return process, [json.loads(line) for line in process.stdout.decode().splitlines()]

    def test_probe_never_needs_a_runtime_or_model(self):
        process, rows = self.run_child('probe')
        self.assertEqual(process.returncode, 0)
        self.assertEqual([row['event'] for row in rows], ['started', 'finished'])
        self.assertTrue(rows[-1]['model_free_launch'])

    def test_actual_child_forwards_locked_config_and_c04_then_copies_raw_json(self):
        process, rows = self.run_child()
        self.assertEqual(process.returncode, 0, process.stderr)
        raw = [row for row in rows if 'native_json_hex' in row]
        self.assertEqual([row['fixture'] for row in raw], ['hello', 'arithmetic'])
        self.assertEqual([json.loads(bytes.fromhex(row['native_json_hex']))['content'][0]['text'] for row in raw], ['Hello!', '7'])
        metrics = [row for row in rows if 'input_tokens' in row]
        self.assertEqual(len(metrics), 2)
        self.assertTrue(all(row['input_tokens'] == 12 and row['output_tokens'] == 3 for row in metrics))
        self.assertTrue(rows[-1]['engine_deleted'])

    def test_guard_never_calls_generation(self):
        process, rows = self.run_child('guard', GUARD='1')
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertTrue(rows[-1]['guard_refused'])
        self.assertFalse(any(row['event'] == 'generation' for row in rows))

    def test_bad_abi_and_null_json_have_no_terminal_success(self):
        for env in ({'WRONG_ABI':'1'}, {'NULL_JSON':'1'}):
            with self.subTest(env=env):
                process, rows = self.run_child(**env)
                self.assertEqual(process.returncode, 1)
                self.assertFalse(any(row['event'] == 'finished' for row in rows))

if __name__ == '__main__':
    unittest.main()
