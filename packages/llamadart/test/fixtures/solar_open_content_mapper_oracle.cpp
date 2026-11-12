#include "chat.h"
#include "chat-peg-parser.h"
#include "json.h"
#include <iostream>

int main(int argc, char ** argv) {
    auto parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
        auto reasoning = p.rule("reasoning", p.atomic(p.literal("<|think|>")) + p.reasoning(p.until("<|end|>")));
        auto content = p.rule("content", p.atomic(p.literal("<|content|>")) + p.content(p.until("<|end|>")));
        auto channel = p.choice({ reasoning, content });
        return channel + p.zero_or_more(p.atomic(p.literal("<|end|>")) + p.atomic(p.literal("<|begin|>assistant")) + channel);
    });
    const std::string input = argc > 1 ? argv[1] : "<|think|>Plan.<|end|><|begin|>assistant<|content|>Sunny. <|end|><|begin|>assistant<|content|> more";
    common_peg_parse_context ctx(input, COMMON_PEG_PARSE_FLAG_LENIENT | COMMON_PEG_PARSE_FLAG_COMPLETE);
    auto parsed = parser.parse(ctx);
    common_json nodes = common_json::array();
    ctx.ast.visit(parsed, [&](const common_peg_ast_node & node) {
        if (node.tag == "content" || node.tag == "reasoning") {
            nodes.push_back({{"tag",node.tag},{"text",std::string(node.text)}});
        }
    });
    common_chat_parser_params params;
    params.format = COMMON_CHAT_FORMAT_PEG_NATIVE;
    auto message = common_chat_peg_parse(parser, common_chat_input(input), false, params);
    common_json output = {{"input", input}, {"scope", "current primary mapper, Dart Solar no-tools grammar; not upstream template admission"}, {"ast",nodes},{"content",message.content},{"reasoning",message.reasoning_content}};
    std::cout << output.dump(2) << std::endl;
}
