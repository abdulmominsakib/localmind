// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'Sua IA. Seu dispositivo. Suas regras.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get delete => 'Excluir';

  @override
  String get save => 'Salvar';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get close => 'Fechar';

  @override
  String get done => 'Concluído';

  @override
  String get continue_action => 'Continuar';

  @override
  String get skip => 'Pular';

  @override
  String get install => 'Instalar';

  @override
  String get download => 'Baixar';

  @override
  String get resume => 'Currículo';

  @override
  String get pause => 'Pausa';

  @override
  String get stop => 'Pare';

  @override
  String get edit => 'Editar';

  @override
  String get preview => 'Visualização';

  @override
  String get unload => 'Descarregar';

  @override
  String get load => 'Carregar';

  @override
  String get rename => 'Renomear';

  @override
  String get pin => 'Fixar';

  @override
  String get unpin => 'Liberar';

  @override
  String get share => 'Compartilhar';

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado!';

  @override
  String get copied_to_clipboard => 'Copiado para a área de transferência';

  @override
  String get select => 'Selecione';

  @override
  String get active => 'Ativo';

  @override
  String get all => 'Todos';

  @override
  String get none => 'Nenhum';

  @override
  String get none_selected => 'Nenhum selecionado';

  @override
  String get online => 'On-line';

  @override
  String get connected => 'Conectado';

  @override
  String get checking => 'Verificando';

  @override
  String get offline => 'Off-line';

  @override
  String get error => 'Erro';

  @override
  String get unknown_error => 'Erro desconhecido';

  @override
  String get not_now => 'Agora não';

  @override
  String get enable => 'Habilitar';

  @override
  String get proceed_anyway => 'Prossiga de qualquer maneira';

  @override
  String get test_connection => 'Conexão de teste';

  @override
  String get testing => 'Testando...';

  @override
  String get connection_successful => 'Conexão bem-sucedida!';

  @override
  String get connection_failed =>
      'Falha na conexão. Verifique suas configurações.';

  @override
  String get save_continue => 'Salvar e continuar';

  @override
  String get save_changes => 'Salvar alterações';

  @override
  String get finish_setup => 'Concluir configuração';

  @override
  String get start_new_chat => 'Iniciar novo bate-papo';

  @override
  String get cannot_undo => 'Esta ação não pode ser desfeita.';

  @override
  String get ram_warning => 'Aviso de RAM';

  @override
  String get recommended => 'RECOMENDADO';

  @override
  String get may_be_large => 'Pode ser muito grande para este dispositivo';

  @override
  String get calculating => 'Calculando...';

  @override
  String get download_failed => 'Falha no download';

  @override
  String get downloaded => 'Baixado';

  @override
  String get not_downloaded => 'Não baixado';

  @override
  String get installed => 'Instalado';

  @override
  String get not_installed => 'Não instalado';

  @override
  String get loading => 'Carregando...';

  @override
  String get thinking => 'Pensando';

  @override
  String get processing => 'Processando...';

  @override
  String get initializing => 'Inicializando...';

  @override
  String get ready => 'Pronto';

  @override
  String get preparing_app => 'Preparando aplicativo...';

  @override
  String get initializing_services => 'Inicializando serviços...';

  @override
  String get configuring_server => 'Configurando servidor...';

  @override
  String get startup_failed => 'Falha na inicialização';

  @override
  String get something_went_wrong => 'Algo deu errado';

  @override
  String get delete_model_title => 'Excluir modelo';

  @override
  String delete_model_body(String name) {
    return 'Tem certeza de que deseja excluir o $name?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Tem certeza de que deseja excluir o $name? Isso liberará aproximadamente $size de espaço.\n\nVocê pode baixar este modelo novamente mais tarde, se necessário.';
  }

  @override
  String get delete_voice_title => 'Excluir voz';

  @override
  String delete_voice_body(String name, String size) {
    return 'Tem certeza de que deseja excluir o $name? Isso liberará aproximadamente $size de espaço.\n\nVocê pode baixar esta voz novamente mais tarde, se necessário.';
  }

  @override
  String get delete_server_title => 'Excluir servidor';

  @override
  String delete_server_body(String name) {
    return 'Tem certeza de que deseja excluir \"$name\"? Isto não pode ser desfeito.';
  }

  @override
  String get delete_conversation_title => 'Excluir conversa?';

  @override
  String delete_conversation_body(String title) {
    return 'Tem certeza de que deseja excluir \"$title\"? Isto não pode ser desfeito.';
  }

  @override
  String get delete_message_title => 'Excluir mensagem?';

  @override
  String delete_persona_title(String name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String get delete_persona_body => 'Isto não pode ser desfeito.';

  @override
  String get delete_builtin_persona_body =>
      'Esta é uma persona embutida. Você pode restaurá-lo mais tarde em Configurações.';

  @override
  String get restore_builtin_personas => 'Restaurar personas padrão';

  @override
  String get restore_builtin_personas_desc =>
      'Adicione novamente quaisquer personas integradas que você excluiu';

  @override
  String get restore_builtin_personas_success => 'Personas padrão restauradas';

  @override
  String get clear_personas => 'Personalidades claras';

  @override
  String get enable_image_compression => 'Compacte imagens antes de enviar';

  @override
  String get enable_image_compression_desc =>
      'Redimensione e compacte imagens anexadas para que os uploads permaneçam dentro dos limites do servidor';

  @override
  String get image_compression_level => 'Agressividade de compressão';

  @override
  String get image_compression_level_desc =>
      'Maior agressividade produz uploads menores com qualidade inferior';

  @override
  String get image_compression_level_low => 'Baixo';

  @override
  String get image_compression_level_medium => 'Médio';

  @override
  String get image_compression_level_high => 'Alto';

  @override
  String get sort_models_tooltip => 'Classificar modelos';

  @override
  String get sort_by_favorites => 'Favoritos primeiro';

  @override
  String get sort_by_name => 'Nome (A-Z)';

  @override
  String get sort_by_size_smallest => 'Tamanho (menor primeiro)';

  @override
  String get sort_by_size_largest => 'Tamanho (maior primeiro)';

  @override
  String get sort_by_context_length => 'Comprimento do contexto';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Renomeando $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '$count selecionado';
  }

  @override
  String get ai_rename_tooltip => 'Renomear selecionado com IA';

  @override
  String get new_chat_in_folder_tooltip => 'Novo bate-papo nesta pasta';

  @override
  String total_tokens_count(int count) {
    return 'Tokens $count';
  }

  @override
  String get smart_replies_use_persona =>
      'Use persona em respostas inteligentes';

  @override
  String get smart_replies_use_persona_desc =>
      'As respostas sugeridas correspondem ao tom da persona ativa, em vez de um assistente genérico';

  @override
  String get keep_persona_on_new_chat => 'Mantenha a persona no novo chat';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Não limpe a(s) persona(s) selecionada(s) após iniciar um novo chat';

  @override
  String get role_swap_button_enabled => 'Mostrar botão de troca de função';

  @override
  String get role_swap_button_enabled_desc =>
      'Mostrar um botão na entrada do chat para enviar sua mensagem como assistente em vez de usuário, sem gerar resposta';

  @override
  String get send_as_user_tooltip => 'Enviar como usuário';

  @override
  String get send_as_assistant_tooltip =>
      'Enviar como assistente (sem resposta)';

  @override
  String get insert_without_generating_tooltip => 'Inserir sem gerar';

  @override
  String get token_usage_title => 'Uso de token';

  @override
  String get total_tokens_label => 'Tokens usados';

  @override
  String get usage_percent_label => 'Contexto usado';

  @override
  String get export_choice_title => 'Exportar';

  @override
  String get export_choice_body => 'Como você gostaria de exportar isso?';

  @override
  String get copy_to_clipboard => 'Copiar para a área de transferência';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Conversas $count exportadas';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Renomear com IA?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'Isso solicitará que a IA gere um novo título para cada uma das conversas selecionadas pelo $count, substituindo os títulos atuais. Isso pode demorar um pouco e não pode ser desfeito.';
  }

  @override
  String get sort_by_modified_date => 'Última modificação';

  @override
  String get sort_by_created_date => 'Data de criação';

  @override
  String get sort_title => 'Classificar';

  @override
  String get clear_conversation_title => 'Conversa clara?';

  @override
  String get clear_conversation_body =>
      'Isso excluirá todas as mensagens desta conversa.';

  @override
  String get clear => 'Limpar';

  @override
  String label_completed(String label) {
    return '$label concluído';
  }

  @override
  String error_with_message(String error) {
    return 'Erro: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Falha na visualização: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Carregando $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Modelo carregado: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Nenhum modelo carregado. Toque em “Gerenciar modelos no dispositivo” para baixar e carregar um modelo.';

  @override
  String loading_model_error(String error) {
    return 'Erro: $error';
  }

  @override
  String get delete_conversation => 'Excluir conversa?';

  @override
  String get nav_history => 'História';

  @override
  String get nav_servers => 'Servidores';

  @override
  String get nav_local_models => 'Modelos Locais';

  @override
  String get nav_tts => 'Texto para fala';

  @override
  String get nav_personas => 'Personagens';

  @override
  String get nav_settings => 'Configurações';

  @override
  String get nav_new_chat => 'Novo bate-papo';

  @override
  String get search_hint => 'Pesquisar conversas...';

  @override
  String get no_server_selected => 'Nenhum servidor selecionado';

  @override
  String get switch_server => 'Trocar servidor';

  @override
  String get switch_server_subtitle => 'Escolha um servidor para se conectar';

  @override
  String get manage_servers => 'Gerenciar servidores';

  @override
  String get open_source => 'Código aberto';

  @override
  String get open_source_desc =>
      'LocalMind é de código aberto. Acompanhe nosso progresso ou contribua no GitHub.';

  @override
  String get star_on_github => 'Estrela no GitHub';

  @override
  String get add_more => 'Adicionar mais';

  @override
  String get on_github => 'no GitHub';

  @override
  String get could_not_open_github => 'Não foi possível abrir o GitHub.';

  @override
  String get settings_title => 'Configurações';

  @override
  String get settings_appearance => 'Aparência';

  @override
  String get settings_language => 'Idioma';

  @override
  String get language_system_default => 'Padrão do sistema';

  @override
  String get settings_tts => 'Conversão de texto para fala';

  @override
  String get settings_android_assistant => 'Assistente Android';

  @override
  String get assistant_default_title => 'Use LocalMind como seu assistente';

  @override
  String get assistant_default_description =>
      'Inicie o modo de voz com o gesto do assistente do Android ou o atalho do botão liga / desliga.';

  @override
  String get assistant_status_active => 'Ativo';

  @override
  String get assistant_status_available => 'Não ativo';

  @override
  String get assistant_status_manual => 'Verifique as configurações';

  @override
  String get assistant_status_unsupported => 'Indisponível';

  @override
  String get assistant_status_checking => 'Verificando…';

  @override
  String get assistant_set_default => 'Definir como assistente padrão';

  @override
  String get assistant_open_settings =>
      'Abra as configurações do assistente Android';

  @override
  String assistant_error(Object error) {
    return 'Não foi possível abrir as configurações do assistente Android.';
  }

  @override
  String get settings_behavior => 'Comportamento';

  @override
  String get settings_on_device => 'Inferência no dispositivo';

  @override
  String get settings_default_server => 'Servidor padrão';

  @override
  String get settings_default_persona => 'Personagem padrão';

  @override
  String get settings_default_model => 'Modelo padrão';

  @override
  String get settings_default_model_desc =>
      'Selecionado automaticamente quando você inicia um novo bate-papo.';

  @override
  String get settings_privacy => 'Privacidade';

  @override
  String get settings_data_management => 'Gerenciamento de dados';

  @override
  String get settings_about => 'Sobre';

  @override
  String get theme => 'Tema';

  @override
  String get theme_system => 'Sistema';

  @override
  String get theme_light => 'Luz';

  @override
  String get theme_dark => 'Escuro';

  @override
  String get theme_claude => 'Cláudio';

  @override
  String get font_size => 'Tamanho da fonte';

  @override
  String get font_size_desc => 'Ajuste o tamanho do texto no chat.';

  @override
  String get font_preview =>
      'A rápida raposa marrom salta sobre o cachorro preguiçoso.';

  @override
  String get code_theme_dark => 'Tema de código (escuro)';

  @override
  String get code_theme_light => 'Tema de código (claro)';

  @override
  String get code_theme_desc =>
      'Escolha o tema de destaque de sintaxe para blocos de código.';

  @override
  String get tts_engine => 'Motor TTS';

  @override
  String get tts_engine_system => 'Sistema TTS';

  @override
  String get tts_engine_kitten => 'Gatinho TTS';

  @override
  String get voice => 'Voz';

  @override
  String get voice_female => 'Feminino';

  @override
  String get voice_male => 'Masculino';

  @override
  String get voice_other => 'Outro';

  @override
  String get tts_speed => 'Velocidade TTS';

  @override
  String get tts_speed_desc => 'Ajuste a taxa de reprodução.';

  @override
  String get manage_tts_models => 'Gerenciar modelos TTS';

  @override
  String get manage_on_device_models => 'Gerenciar modelos no dispositivo';

  @override
  String get enable_smart_reply => 'Respostas inteligentes no dispositivo';

  @override
  String get ai_user_response_enabled =>
      'Mensagem do usuário AI (manter envio)';

  @override
  String get ai_user_response_enabled_desc =>
      'Segure o botão enviar por 3 segundos para que a IA escreva e envie sua próxima mensagem';

  @override
  String get ai_user_response_tooltip => 'Gere mensagem do usuário com IA';

  @override
  String get streaming_responses => 'Respostas de streaming';

  @override
  String get auto_generate_titles => 'Gerar títulos automaticamente';

  @override
  String get send_on_enter => 'Enviar ao entrar';

  @override
  String get show_system_messages => 'Enviar prompt padrão do sistema';

  @override
  String get show_system_messages_desc =>
      'Quando nenhuma persona for selecionada, envie um prompt padrão do sistema do assistente com cada solicitação';

  @override
  String get show_system_messages_in_chat =>
      'Mostrar mensagens do sistema no bate-papo';

  @override
  String get show_system_messages_in_chat_desc =>
      'Exibir mensagens do sistema (por exemplo, de um backup importado) como balões visíveis na conversa';

  @override
  String get auto_collapse_thinking => 'Pensamento de colapso automático';

  @override
  String get auto_collapse_thinking_desc =>
      'Recolher automaticamente o processo de raciocínio após a geração da resposta ser concluída quando uma resposta principal estiver presente';

  @override
  String get haptic_feedback => 'Feedback tátil';

  @override
  String get enable_mcp => 'Habilitar MCP';

  @override
  String get new_chat_mcp_default => 'Novo padrão MCP de bate-papo';

  @override
  String get show_data_indicator => 'Mostrar indicador de dados';

  @override
  String get privacy_info => '\"LocalMind nunca vê seus dados\"';

  @override
  String get delete_all_conversations => 'Excluir todas as conversas';

  @override
  String get reset_settings_defaults =>
      'Redefinir as configurações para os padrões';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Parâmetros de bate-papo';

  @override
  String get change_persona => 'Mudar de personalidade';

  @override
  String get set_persona => 'Definir personalidade';

  @override
  String get remove_persona => 'Remover personalidade';

  @override
  String get clear_conversation => 'Conversa clara';

  @override
  String get connection_error => 'Erro de conexão. Verifique seu servidor.';

  @override
  String get disconnected => 'Desconectado do servidor.';

  @override
  String get configure => 'Configurar';

  @override
  String get select_model => 'Selecione o modelo';

  @override
  String get select_persona => 'Selecione a personalidade';

  @override
  String get manage_personas => 'Gerenciar personas';

  @override
  String get personas_combine_hint =>
      'Selecione várias personas no chat para empilhar as solicitações do sistema.';

  @override
  String get start_conversation => 'Inicie uma conversa';

  @override
  String get recent_chats => 'Bate-papos recentes';

  @override
  String get see_all => 'Ver tudo';

  @override
  String get quick_write => 'Ajude-me a escrever uma função';

  @override
  String get quick_explain => 'Explique este código';

  @override
  String get quick_debug => 'Depure isso para mim';

  @override
  String get quick_async => 'Como faço para usar assíncrono/aguardar?';

  @override
  String get history_missing_title => 'História ausente';

  @override
  String get history_missing_desc =>
      'As mensagens neste bate-papo foram excluídas ou o registro do histórico está corrompido.';

  @override
  String get technical_details => 'Detalhes técnicos';

  @override
  String get last_error => 'Último erro:';

  @override
  String get copy_info => 'Copiar informações';

  @override
  String get conversation_id => 'ID da conversa';

  @override
  String get created_at => 'Criado em';

  @override
  String get expected_messages => 'Mensagens esperadas';

  @override
  String get debug_dialog_desc =>
      'Informações de diagnóstico para ajudar a identificar problemas de sincronização.';

  @override
  String get chat_input_hint => 'Pergunte qualquer coisa';

  @override
  String get send_message_tooltip => 'Enviar mensagem';

  @override
  String get stop_generation_tooltip => 'Parar geração';

  @override
  String get attach_images_tooltip => 'Anexe imagens ou texto';

  @override
  String get start_listening_tooltip => 'Comece a ouvir';

  @override
  String get stop_listening_tooltip => 'Pare de ouvir';

  @override
  String tool_label(String toolCallId) {
    return 'Ferramenta: $toolCallId';
  }

  @override
  String get tool_unknown => 'Ferramenta: Desconhecida';

  @override
  String get message_options => 'Opções de mensagem';

  @override
  String get copy_markdown => 'Copiar como Markdown';

  @override
  String get copied_markdown => 'Copiado como Markdown';

  @override
  String get read_aloud => 'Leia em voz alta';

  @override
  String get stop_reading => 'Pare de ler';

  @override
  String get more => 'Mais';

  @override
  String character_count(int length) {
    return 'Caracteres $length';
  }

  @override
  String get edit_message => 'Editar mensagem';

  @override
  String get edit_message_desc =>
      'Salvar removerá a resposta do assistente abaixo e a regenerará.';

  @override
  String get save_regenerate => 'Salvar e regenerar';

  @override
  String get chat_settings_title => 'Configurações de bate-papo';

  @override
  String get reset_defaults => 'Redefinir padrões';

  @override
  String get parameters_tab => 'Parâmetros';

  @override
  String get mcp_tab => 'PCM';

  @override
  String get temperature => 'Temperatura';

  @override
  String get temperature_desc =>
      'Controla a aleatoriedade: Superior = Criativo, Inferior = Focado';

  @override
  String get top_p => 'Parte superior P';

  @override
  String get top_p_desc => 'Limite de amostragem de núcleo';

  @override
  String get max_tokens => 'Máximo de tokens';

  @override
  String get max_tokens_desc => 'Limite de resposta';

  @override
  String get context_length => 'Comprimento do contexto';

  @override
  String get context_length_desc => 'Janela de histórico';

  @override
  String get mcp_disabled_warning =>
      'O MCP está desabilitado globalmente. Ative-o em Configurações para usar esses recursos.';

  @override
  String get mcp_enable_chat => 'Habilite o MCP para este chat';

  @override
  String get auto_execute_tools => 'Ferramentas de execução automática';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Experimental';

  @override
  String get add_ephemeral_mcp => 'Adicionar servidor MCP efêmero';

  @override
  String get mcp_label_placeholder => 'Etiqueta';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => 'Integrações Ativas';

  @override
  String get import_mcp_json => 'Importar JSON';

  @override
  String get import_mcp_json_dialog_title =>
      'Importar JSON de configuração do MCP';

  @override
  String get import_mcp_json_instructions =>
      'Copie seu JSON mcpServers diretamente do LM Studio (mcp.json) ou cole um array de plugins abaixo:';

  @override
  String get import_mcp_json_placeholder =>
      'Cole mcpServers JSON ou lista de plugins aqui...';

  @override
  String mcp_import_success(int count) {
    return 'Integrações $count importadas com sucesso';
  }

  @override
  String get mcp_import_failed =>
      'Nenhuma integração MCP válida encontrada em JSON';

  @override
  String get enable_notifications => 'Habilitar notificações';

  @override
  String get enable_notifications_desc =>
      'Seja notificado quando o download dos modelos terminar.';

  @override
  String get chat_history_title => 'Histórico de bate-papo';

  @override
  String get conversation_just_now => 'Agora mesmo';

  @override
  String conversation_minutes_ago(int minutes) {
    return '${minutes}m atrás';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '${hours}h atrás';
  }

  @override
  String get conversation_yesterday => 'Ontem';

  @override
  String conversation_days_ago(int days) {
    return '${days}d atrás';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => 'Opções';

  @override
  String get no_results_found => 'Nenhum resultado encontrado';

  @override
  String get no_conversations_yet => 'Ainda não há conversas';

  @override
  String get try_different_search =>
      'Experimente um termo de pesquisa diferente';

  @override
  String get start_new_conversation => 'Inicie uma nova conversa';

  @override
  String get rename_conversation => 'Renomear conversa';

  @override
  String get enter_new_title => 'Insira o novo título';

  @override
  String get pinned_section => 'FIXADO';

  @override
  String get today_section => 'HOJE';

  @override
  String get yesterday_section => 'ONTEM';

  @override
  String get previous_7_days => '7 DIAS ANTERIORES';

  @override
  String get previous_30_days => '30 DIAS ANTERIORES';

  @override
  String get older_section => 'MAIS ANTIGO';

  @override
  String get onboarding_choose_language => 'Escolha o idioma';

  @override
  String get onboarding_choose_language_desc =>
      'Selecione seu idioma preferido. Você pode alterar isso a qualquer momento nas configurações.';

  @override
  String get onboarding_localmind => 'MENTE LOCAL';

  @override
  String get onboarding_connect_server => 'Conecte seu\nServidor';

  @override
  String get onboarding_connect_desc =>
      'Conecte-se ao LM Studio, Ollama,\nOllama Cloud ou OpenRouter para\ncomece sua experiência privada de IA.';

  @override
  String get openai_compatible_api => 'API compatível com OpenAI';

  @override
  String get https_requires_ssl => 'HTTPS requer SSL';

  @override
  String get most_local_setups_use_http =>
      'A maioria das configurações locais usa http://';

  @override
  String get onboarding_welcome => 'Bem-vindo à LocalMind';

  @override
  String get server_type_on_device => 'No dispositivo';

  @override
  String get server_type_lm_studio => 'Estúdio LM';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Nuvem de Ollama';

  @override
  String get server_type_ollama_cloud_sub => 'GERENCIADO NA NUVEM';

  @override
  String get server_type_ollama_cloud_display => 'Nuvem de Ollama';

  @override
  String get server_address_ollama_cloud => 'ollama. com';

  @override
  String get ollama_cloud_disclosure =>
      'Ao conectar o Ollama Cloud, suas mensagens de bate-papo e entradas são enviadas aos servidores gerenciados do Ollama para inferência. LocalMind não rastreia nem armazena suas conversas. Você pode revogar essa chave a qualquer momento em ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud =>
      'Chave de API necessária para Ollama Cloud';

  @override
  String get api_key_hint_ollama_cloud =>
      'Cole sua chave de API do Ollama Cloud';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Conecte-se ao Ollama Cloud com uma chave de API em ollama.com/settings/keys para acessar modelos de nuvem gerenciados.';

  @override
  String get add_server_openrouter_subtitle =>
      'Conecte-se através do OpenRouter com uma chave de API válida e mantenha este perfil pronto para roteamento de modelo.';

  @override
  String get add_server_endpoint_subtitle =>
      'Configure um endpoint local ou auto-hospedado e verifique a conexão antes de salvar.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => 'NUVEM UNIFICADA';

  @override
  String get ready_continue => 'PRONTO PARA CONTINUAR';

  @override
  String get waiting_selection => 'AGUARDANDO SELEÇÃO';

  @override
  String get setup_connection => 'Configurar conexão';

  @override
  String setup_connection_desc(String server) {
    return 'Configure seu servidor $server para começar a conversar.';
  }

  @override
  String get server_name => 'Nome do servidor';

  @override
  String get name_required => 'Nome obrigatório';

  @override
  String get name_max_50 => 'Máximo de 50 caracteres';

  @override
  String get host_label => 'Host/Endereço IP';

  @override
  String get host_required => 'Anfitrião necessário';

  @override
  String get port_label => 'Porto';

  @override
  String get port_required => 'Porta necessária';

  @override
  String get port_invalid => 'Deve ser um número';

  @override
  String get port_range => 'Insira uma porta válida (1-65535)';

  @override
  String get api_key_required => 'Chave API *';

  @override
  String get api_key_optional => 'Chave de API (opcional)';

  @override
  String get api_key_required_openrouter =>
      'Chave de API necessária para OpenRouter';

  @override
  String get api_key_format => 'As chaves da API OpenRouter começam com sk-';

  @override
  String get my_server_hint => 'Meu servidor';

  @override
  String get name_length_validation => 'O nome deve ter 50 caracteres ou menos';

  @override
  String get host_valid => 'Insira um nome de host ou endereço IP válido';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => 'Para servidores autenticados';

  @override
  String get update_server => 'Servidor de atualização';

  @override
  String get save_server => 'Salvar servidor';

  @override
  String get server_updated => 'Servidor atualizado';

  @override
  String get server_added => 'Servidor adicionado';

  @override
  String get download_model_title => 'Baixe um modelo';

  @override
  String get download_model_desc =>
      'Escolha um modelo para baixar.\nEle será executado localmente no seu dispositivo.';

  @override
  String get on_device_android_only =>
      'Atualmente, a inferência no dispositivo está disponível apenas no Android.';

  @override
  String get total_ram => 'RAM total';

  @override
  String get available => 'Disponível';

  @override
  String ram_min_required(String fileSize) {
    return '$fileSize GB de RAM mínimo';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Hora prevista de chegada: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'Pausado - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Este modelo requer pelo menos $ram GB de RAM, mas seu dispositivo possui $totalMemory. Ele pode não funcionar corretamente ou causar falha no aplicativo.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Seu dispositivo possui RAM disponível $availableRAM, mas este modelo recomenda pelo menos $ram GB. Carregá-lo pode falhar ou causar instabilidade.';
  }

  @override
  String get choose_theme => 'Escolha o tema';

  @override
  String get choose_theme_desc =>
      'Personalize a aparência do aplicativo. Você sempre pode alterar isso mais tarde nas configurações.';

  @override
  String get theme_card_system => 'Sistema';

  @override
  String get theme_card_system_sub =>
      'Corresponde às configurações do seu dispositivo';

  @override
  String get theme_card_light => 'Luz';

  @override
  String get theme_card_light_sub => 'Limpo e brilhante';

  @override
  String get theme_card_dark => 'Escuro';

  @override
  String get theme_card_dark_sub => 'Fácil para os olhos';

  @override
  String get theme_card_claude => 'Cláudio';

  @override
  String get theme_card_claude_sub => 'Um tema quente com tons de pêssego';

  @override
  String get stay_updated => 'Fique atualizado';

  @override
  String get stay_updated_desc =>
      'Seja notificado quando o download dos seus modelos de IA terminar ou quando tarefas de longa execução forem concluídas.';

  @override
  String get notification_benefit_downloads =>
      'Progresso do download do modelo';

  @override
  String get notification_benefit_completions => 'Conclusões de geração';

  @override
  String get notification_benefit_background =>
      'Status das tarefas em segundo plano';

  @override
  String get allow_notifications => 'Permitir notificações';

  @override
  String get servers_title => 'Servidores';

  @override
  String get no_servers_yet => 'Ainda não há servidores';

  @override
  String get no_servers_desc =>
      'Adicione seu primeiro servidor para começar a conversar com modelos de IA.';

  @override
  String get add_server => 'Adicionar servidor';

  @override
  String switched_to_server(String name) {
    return 'Mudou para $name';
  }

  @override
  String get edit_server => 'Editar servidor';

  @override
  String get add_server_title => 'Adicionar servidor';

  @override
  String get server_type_label => 'Tipo de servidor';

  @override
  String get server_icon_label => 'Ícone do servidor';

  @override
  String get default_icon => 'Ícone padrão';

  @override
  String get server_type_lm_studio_display => 'Estúdio LM';

  @override
  String get server_type_openai_display => 'Compatível com OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'No dispositivo';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'Inferência local';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Padrão';

  @override
  String get set_as_default => 'Definir como padrão';

  @override
  String get select_icon => 'Selecione o ícone';

  @override
  String get select_icon_desc => 'Escolha um ícone para o seu servidor';

  @override
  String get search_icons_hint => 'Pesquisar ícones...';

  @override
  String get server_icon_stack => 'Pilha de servidores';

  @override
  String get server_icon_stack2 => 'Pilha de servidores 02';

  @override
  String get server_icon_stack3 => 'Pilha de servidores 03';

  @override
  String get server_icon_cloud => 'Nuvem';

  @override
  String get server_icon_cloud_server => 'Servidor em nuvem';

  @override
  String get server_icon_mcp => 'Servidor MCP';

  @override
  String get server_icon_database => 'Banco de dados';

  @override
  String get server_icon_database1 => 'Banco de dados 01';

  @override
  String get server_icon_database2 => 'Banco de dados 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'Chip';

  @override
  String get server_icon_chip2 => 'Ficha 02';

  @override
  String get server_icon_computer => 'Computador';

  @override
  String get server_icon_laptop => 'Portátil';

  @override
  String get server_icon_terminal => 'Terminal de computador';

  @override
  String get server_icon_code => 'Código';

  @override
  String get server_icon_ai_brain => 'Cérebro de IA';

  @override
  String get server_icon_ai_brain2 => 'Cérebro IA 02';

  @override
  String get server_icon_ai_cloud => 'Nuvem de IA';

  @override
  String get server_icon_ai_network => 'Rede de IA';

  @override
  String get server_icon_ai_chat => 'Bate-papo com IA';

  @override
  String get server_icon_cellular => 'Rede Celular';

  @override
  String get server_icon_plug1 => 'Plugue 01';

  @override
  String get server_icon_plug2 => 'Plugue 02';

  @override
  String get server_icon_bot => 'Robô';

  @override
  String get server_icon_bot2 => 'Robô 02';

  @override
  String get server_icon_robotic => 'Robótico';

  @override
  String get server_icon_rocket => 'Foguete';

  @override
  String get server_icon_star => 'Estrela';

  @override
  String get server_icon_settings1 => 'Configurações 01';

  @override
  String get server_icon_settings2 => 'Configurações 02';

  @override
  String get server_icon_home1 => 'Casa 01';

  @override
  String get server_icon_home2 => 'Casa 02';

  @override
  String get server_icon_folder1 => 'Pasta 01';

  @override
  String get server_icon_folder2 => 'Pasta 02';

  @override
  String get server_icon_file1 => 'Arquivo 01';

  @override
  String get server_icon_lock => 'Bloquear';

  @override
  String get server_icon_key => 'Chave 01';

  @override
  String get server_icon_link => 'Ligação 01';

  @override
  String get server_icon_globe => 'Globo';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Seta para a Direita 01';

  @override
  String get server_icon_check => 'Verifique o círculo';

  @override
  String get server_icon_alert => 'Círculo de Alerta';

  @override
  String get server_icon_info => 'Círculo de Informações';

  @override
  String get server_icon_zap => 'Zap';

  @override
  String get server_icon_cloud_upload => 'Carregamento na nuvem';

  @override
  String get server_icon_cloud_download => 'Download na nuvem';

  @override
  String get server_icon_refresh => 'Atualizar';

  @override
  String get server_icon_hard_drive => 'Disco rígido';

  @override
  String get server_icon_drive => 'Dirigir';

  @override
  String get personas_title => 'Personagens';

  @override
  String get persona_category_general => 'Geral';

  @override
  String get persona_category_coding => 'Codificação';

  @override
  String get persona_category_education => 'Educação';

  @override
  String get persona_category_creative => 'Criativo';

  @override
  String get persona_builtin_section => 'INTEGRADO';

  @override
  String get persona_my_section => 'MINHAS PESSOAS';

  @override
  String get clone_edit => 'Clonar e editar';

  @override
  String get builtin_badge => 'Integrado';

  @override
  String get no_personas_found => 'Nenhuma persona encontrada';

  @override
  String get no_personas_desc =>
      'Crie sua primeira persona para personalizar o comportamento da IA.';

  @override
  String get edit_persona => 'Editar personalidade';

  @override
  String get create_persona => 'Criar personalidade';

  @override
  String get create_persona_button => 'Criar';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'Nome';

  @override
  String get my_persona_hint => 'Minha personalidade';

  @override
  String get category_label => 'Categoria';

  @override
  String get description_optional => 'Descrição (opcional)';

  @override
  String get description_hint => 'O que essa pessoa faz...';

  @override
  String get system_prompt => 'Alerta do sistema';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Nenhum aviso ainda...';

  @override
  String get prompt_hint => 'Você é um assistente prestativo...';

  @override
  String get prompt_required => 'O prompt do sistema é obrigatório';

  @override
  String get prompt_max_chars => 'Máximo de 4.000 caracteres';

  @override
  String get advanced_settings => 'Configurações avançadas';

  @override
  String get temperature_label => 'Temperatura (0,0-2,0)';

  @override
  String get top_p_label => 'P superior (0,0-1,0)';

  @override
  String get temp_hint => '0,7';

  @override
  String get top_p_hint => '0,9';

  @override
  String get range_0_2 => '0,0-2,0';

  @override
  String get range_0_1 => '0,0-1,0';

  @override
  String get persona_updated => 'Personagem atualizada';

  @override
  String get persona_created => 'Personagem criada';

  @override
  String get tts_models_title => 'Modelos de texto para fala';

  @override
  String get always_available => 'Sempre disponível';

  @override
  String get tts_system_desc =>
      'Usa o mecanismo de conversão de texto em fala integrado do seu dispositivo.\nNão são necessários downloads. A seleção de voz usa as configurações do sistema do seu dispositivo.';

  @override
  String get downloading_status => 'Baixando...';

  @override
  String tts_kitten_desc(String size) {
    return 'TTS neural ultrarrápido com 8 vozes expressivas.\nRequer download do $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Vozes offline rápidas do Piper com 2 vozes expressivas.\nRequer download de $size por voz.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · Vozes $voiceCount';
  }

  @override
  String get on_device_models_title => 'Modelos no dispositivo';

  @override
  String get settings_huggingface_token =>
      'Abraçando o token de rosto (opcional)';

  @override
  String get settings_huggingface_token_desc =>
      'Necessário apenas para modelos fechados (por exemplo, Gemma). Obtenha um token em huggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Token salvo';

  @override
  String get settings_huggingface_token_cleared => 'Token limpo';

  @override
  String get model_requires_huggingface_token =>
      'Requer um token de Rosto Abraçado';

  @override
  String get model_missing_huggingface_token =>
      'Este modelo está bloqueado no Hugging Face. Adicione um token em Configurações → Inferência no dispositivo para baixá-lo.';

  @override
  String get set_huggingface_token => 'Definir token';

  @override
  String get clear_huggingface_token => 'Limpar';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Abraçando o token de acesso facial';

  @override
  String get huggingface_token_dialog_hint => 'ah_…';

  @override
  String get server_type_ollama_desc =>
      'Mecanismo de IA local. Nenhuma chave de API é necessária.';

  @override
  String get server_type_on_device_desc =>
      'Funciona no seu telefone. Alguns modelos precisam de um token Hugging Face.';

  @override
  String get server_type_lm_studio_desc =>
      'Servidor API local. Nenhuma chave de API é necessária.';

  @override
  String get available_models => 'Modelos Disponíveis';

  @override
  String get device_memory => 'Memória do dispositivo';

  @override
  String get ram_usage => 'Uso de RAM';

  @override
  String get memory_healthy => 'Saudável';

  @override
  String get memory_critical => 'Crítico';

  @override
  String get memory_low => 'Baixo';

  @override
  String ram_used(String percent) {
    return '$percent% usado';
  }

  @override
  String get available_ram => 'RAM disponível';

  @override
  String get total_capacity => 'Capacidade total';

  @override
  String get loaded_status => 'Carregado';

  @override
  String get inference_backend => 'Back-end de inferência';

  @override
  String get backend_ios_notice =>
      'Apenas o back-end da CPU está disponível no iOS.';

  @override
  String get backend_cpu_desc =>
      'Funciona em todos os dispositivos. Mais compatível.';

  @override
  String get backend_gpu_desc =>
      'Aceleração OpenCL. Mais rápido em dispositivos suportados.';

  @override
  String get backend_npu_desc =>
      'NPU do fornecedor (Qualcomm/MediaTek). Inferência mais rápida.';

  @override
  String get select_model_title => 'Selecione o modelo';

  @override
  String get refresh_models => 'Atualizar modelos';

  @override
  String get search_models_hint => 'Pesquisar modelos...';

  @override
  String get no_server_connected => 'Nenhum servidor conectado';

  @override
  String get add_server_first =>
      'Adicione um servidor primeiro para ver os modelos disponíveis.';

  @override
  String get failed_load_models => 'Falha ao carregar modelos';

  @override
  String get no_models_available => 'Nenhum modelo disponível';

  @override
  String no_models_match(String searchQuery) {
    return 'Nenhum modelo corresponde a \"$searchQuery\"';
  }

  @override
  String model_load_failed(String error) {
    return 'Falha ao carregar modelo: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'Descarregamento solicitado para $name. Se Ollama estiver acessível, o modelo será liberado imediatamente.';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name descarregado com sucesso';
  }

  @override
  String model_unload_failed(String error) {
    return 'Falha ao descarregar modelo: $error';
  }

  @override
  String get unload_from_server => 'Descarregar do servidor';

  @override
  String context_chip(String ctx) {
    return '$ctx ctx';
  }

  @override
  String get unload_all_models => 'Descarregar tudo';

  @override
  String loaded_models_count(int count) {
    return '$count carregado';
  }

  @override
  String get all_models_unloaded => 'Todos os modelos descarregados';

  @override
  String get branch_chat => 'Bate-papo da filial';

  @override
  String get branch_chat_desc =>
      'Iniciar uma nova conversa a partir desta mensagem';

  @override
  String get edit_assistant_message_desc =>
      'Edite o texto da resposta do assistente.';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Mudar para $modelName';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Baixando $modelName...';
  }

  @override
  String get download_complete_notification => 'Download concluído!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName foi baixado com sucesso.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Falha no download: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Falha ao baixar $modelName.';
  }

  @override
  String get engine_name_system => 'Sistema TTS';

  @override
  String get engine_tagline_system => 'Mecanismo de dispositivo integrado';

  @override
  String get engine_name_kitten => 'Gatinho TTS';

  @override
  String get engine_tagline_kitten => 'TTS neural de alta velocidade';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'Vozes off-line do Piper';

  @override
  String get voice_jasper => 'Jaspe';

  @override
  String get voice_bella => 'Bela';

  @override
  String get voice_bruno => 'Bruno';

  @override
  String get voice_luna => 'Lua';

  @override
  String get voice_hugo => 'Hugo';

  @override
  String get voice_rosie => 'Rosie';

  @override
  String get voice_leo => 'Leão';

  @override
  String get voice_kiki => 'Kiki';

  @override
  String get voice_lessac => 'Lessac (EUA)';

  @override
  String get voice_ryan => 'Ryan (EUA)';

  @override
  String get model_qwen_3 => 'Qwen3 0,6B';

  @override
  String get model_qwen_3_desc =>
      'O menor modelo de chat de uso geral. Respostas rápidas, baixo uso de memória.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Instrução Qwen 2.5 1.5B';

  @override
  String get model_qwen_25_desc =>
      'Qualidade e tamanho equilibrados. Bom para conversas gerais.';

  @override
  String get model_deepseek => 'DeepSeek R1 Destilar Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Modelo de raciocínio e cadeia de pensamento. Melhor para tarefas lógicas.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Instrução Gemma 4 E2B';

  @override
  String get model_gemma_desc =>
      'Modelo carro-chefe do Google. A mais alta qualidade, requer mais RAM.';

  @override
  String export_header(String date) {
    return '*Exportado de LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Usuário';

  @override
  String get export_role_assistant => '## 🤖 Assistente';

  @override
  String get export_role_system => '## ⚙️ Sistema';

  @override
  String get export_role_tool => '## 🔧 Ferramenta';

  @override
  String get export_text_user => '[USUÁRIO]';

  @override
  String get export_text_assistant => '[ASSISTENTE]';

  @override
  String get export_text_system => '[SISTEMA]';

  @override
  String get export_text_tool => '[FERRAMENTA]';

  @override
  String get export_label_user => 'USUÁRIO';

  @override
  String get export_label_assistant => 'ASSISTENTE';

  @override
  String get export_label_system => 'SISTEMA';

  @override
  String get export_label_tool => 'FERRAMENTA';

  @override
  String get select_model_hint =>
      'Selecione um modelo para começar a conversar';

  @override
  String get test_notification_title => 'Notificação de teste';

  @override
  String get test_notification_body =>
      'Esta é uma notificação de teste para o progresso do download do modelo.';

  @override
  String get tts_supports_background =>
      'Suporta reprodução em segundo plano como áudio nativo';

  @override
  String get tts_other_services_background_note =>
      'Nota: Os outros serviços TTS suportam reprodução em segundo plano como áudio nativo.';

  @override
  String get gguf_imported_models_title => 'Modelos GGUF importados';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Importe um GGUF do seu dispositivo ou adicione um do Hugging Face. Os modelos importados são executados localmente com llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      'modelos importados prontos para inferência local.';

  @override
  String get gguf_curated_models_subtitle =>
      'Modelos selecionados no dispositivo que você pode baixar e gerenciar dentro do LocalMind.';

  @override
  String get gguf_only_supported =>
      'Somente modelos GGUF são suportados para esta importação.';

  @override
  String get gguf_imported_from_local_file => 'importado do arquivo local.';

  @override
  String get gguf_import_failed => 'Falha ao importar o modelo GGUF';

  @override
  String get gguf_imported_from_huggingface => 'importado de Hugging Face.';

  @override
  String get gguf_import_canceled => 'Importação de GGUF cancelada.';

  @override
  String get gguf_enter_huggingface_url =>
      'Insira um URL GGUF de rosto abraçado.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Apenas URLs oficiais do Hugging Face GGUF são suportados.';

  @override
  String get gguf_use_https_url =>
      'Use um URL HTTPS Hugging Face para importação de GGUF.';

  @override
  String get gguf_url_must_point_to_file =>
      'O URL do Hugging Face deve apontar diretamente para um arquivo .gguf.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Não foi possível determinar o nome do arquivo GGUF.';

  @override
  String get gguf_download_empty =>
      'O arquivo GGUF baixado estava vazio ou ausente.';

  @override
  String get gguf_selected_file_missing =>
      'O arquivo de modelo selecionado não existe.';

  @override
  String get gguf_import_action => 'Importar GGUF';

  @override
  String get gguf_overview_title => 'Traga seus próprios modelos GGUF';

  @override
  String get gguf_overview_subtitle =>
      'Importe um .gguf do armazenamento local ou baixe um diretamente do Hugging Face. Os modelos importados permanecem neste dispositivo e carregam com llama.cpp.';

  @override
  String get gguf_imported_count_label => 'importado';

  @override
  String get gguf_local_files_label => 'arquivos locais';

  @override
  String get gguf_huggingface_label => 'Abraçando o rosto';

  @override
  String get gguf_import_local_title => 'Importar GGUF local';

  @override
  String get gguf_import_local_subtitle =>
      'Copie um arquivo .gguf deste dispositivo';

  @override
  String get gguf_import_huggingface_title => 'Importar do rosto que abraça';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Cole um URL GGUF ou caminho de repositório';

  @override
  String get gguf_no_imported_title => 'Nenhum modelo GGUF importado ainda';

  @override
  String get gguf_no_imported_subtitle =>
      'Você pode trazer seu próprio arquivo GGUF do armazenamento do dispositivo ou colar um URL do Hugging Face ou um caminho de repositório que aponte para um arquivo .gguf.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Importar GGUF do Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Cole um URL direto do GGUF ou um caminho de repositório Hugging Face como `owner/repo/blob/main/model.gguf`. Os links de blob são convertidos automaticamente.';

  @override
  String get gguf_url_or_repo_path => 'URL GGUF ou caminho do repositório';

  @override
  String get paste => 'Colar';

  @override
  String get gguf_browse => 'Navegar pelos GGUFs';

  @override
  String get gguf_huggingface_token_ready => 'Abraçando o token Face pronto';

  @override
  String get gguf_huggingface_token_optional =>
      'Token opcional, mas recomendado';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Seu token salvo será usado automaticamente para repositórios fechados ou privados.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Requer uma ficha de Abraço de Rosto. Adicione um em Configurações se este GGUF for fechado ou privado.';

  @override
  String get gguf_downloading => 'Baixando GGUF';

  @override
  String get gguf_preparing => 'Preparando';

  @override
  String get gguf_preparing_download => 'Preparando download...';

  @override
  String get gguf_cancel_import => 'Cancelar importação';

  @override
  String get clipboard_empty => 'A área de transferência está vazia.';

  @override
  String get could_not_open_huggingface =>
      'Não foi possível abrir o Hugging Face.';

  @override
  String get gguf_paste_url_error =>
      'Cole um URL do Hugging Face GGUF ou um caminho de repositório.';

  @override
  String get gguf_blob_link => 'Link do blob';

  @override
  String get gguf_repository_label => 'Repositório';

  @override
  String get gguf_detected_path_label => 'Caminho detectado';

  @override
  String get gguf_imported_section_label => 'GGUF importado';

  @override
  String get gguf_already_available => 'Já disponível neste dispositivo';

  @override
  String get gguf_curated_models_short => 'Modelos selecionados no dispositivo';

  @override
  String get execute_tool_title => 'Executar ferramenta';

  @override
  String get execute_tool_request_desc =>
      'O modelo está solicitando a execução da seguinte ferramenta:';

  @override
  String get reject => 'Rejeitar';

  @override
  String get approve => 'Aprovar';

  @override
  String get server_type_help =>
      'Escolha o provedor antes de preencher os detalhes da conexão.';

  @override
  String get server_identity_title => 'Identidade';

  @override
  String get server_identity_desc =>
      'Nomeie este servidor e escolha como ele aparece na lista.';

  @override
  String get server_connection_title => 'Conexão';

  @override
  String get server_connection_desc =>
      'Use o endereço e a porta expostos pelo seu servidor.';

  @override
  String get server_authentication_title => 'Autenticação';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter requer uma chave API antes do teste.';

  @override
  String get server_authentication_optional_desc =>
      'Deixe a chave de API vazia se este servidor não exigir uma.';

  @override
  String get mcp_tools_title => 'Ferramentas MCP';

  @override
  String get available_tools => 'Ferramentas disponíveis';

  @override
  String get unable_load_tools => 'Não foi possível carregar ferramentas';

  @override
  String get no_tools_registered => 'Nenhuma ferramenta cadastrada';

  @override
  String get no_tools_registered_desc =>
      'Ative o servidor MCP de exemplo ou adicione integrações MCP nas configurações de chat.';

  @override
  String get example_mcp_server_title => 'Exemplo de servidor MCP';

  @override
  String get example_mcp_server_desc =>
      'Registra example.echo e example.word_count por meio do mesmo provedor de ferramentas MCP usado por servidores externos.';

  @override
  String get disable_example_server => 'Desativar servidor de exemplo';

  @override
  String get enable_example_server => 'Habilitar servidor de exemplo';

  @override
  String get built_in_label => 'Integrado';

  @override
  String get highlights_label => 'Destaques';

  @override
  String get built_with_label => 'Construído com';

  @override
  String get local_label => 'Locais';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => 'Solicitado';

  @override
  String get tool_status_approved => 'Aprovado';

  @override
  String get tool_status_rejected => 'Rejeitado';

  @override
  String get tool_status_running => 'Correndo';

  @override
  String get tool_status_done => 'Concluído';

  @override
  String get tool_status_failed => 'Falha';

  @override
  String get model_favorite_toggle => 'Alternar favorito';

  @override
  String get model_set_default => 'Definir como modelo padrão';

  @override
  String get model_clear_default => 'Remover como modelo padrão';

  @override
  String get model_default_badge => 'Padrão';

  @override
  String get model_note_label => 'Nota';

  @override
  String get model_note_hint => 'Adicione uma observação sobre este modelo…';

  @override
  String get unload_models_before_load =>
      'Descarregue todos os modelos antes de carregar um novo';

  @override
  String get temp_chat_keyboard_incognito =>
      'Teclado anônimo em bate-papo temporário';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Desativa o aprendizado do teclado e sugestões em bate-papos temporários (por exemplo, SwiftKey incógnito).';

  @override
  String get resume_last_chat => 'Retomar o último bate-papo no lançamento';

  @override
  String get resume_last_chat_desc =>
      'Restaure sua última conversa aberta ao reabrir o aplicativo.';

  @override
  String get export_all_data => 'Exportar todos os dados';

  @override
  String get import_all_data => 'Importe todos os dados';

  @override
  String get export_data_success => 'Backup exportado com sucesso';

  @override
  String get import_data_success => 'Backup importado com sucesso';

  @override
  String import_data_failed(String error) {
    return 'Falha ao importar backup: $error';
  }

  @override
  String get import_data_confirm =>
      'Importar conversas e personas personalizadas deste backup? Os itens existentes com os mesmos IDs serão atualizados.';

  @override
  String get import_settings_confirm =>
      'Substituir as configurações atuais pelo backup importado?';

  @override
  String get export_conversations => 'Exportar conversas';

  @override
  String get import_conversations => 'Importar conversas';

  @override
  String get export_personas => 'Exportar personas';

  @override
  String get import_personas => 'Importar personas';

  @override
  String get export_settings => 'Exportar configurações';

  @override
  String get import_settings => 'Importar configurações';

  @override
  String get export_all_zip => 'Exportar tudo (ZIP)';

  @override
  String get import_all_zip => 'Importar tudo (ZIP)';

  @override
  String get duplicate_chat => 'Bate-papo duplicado';

  @override
  String get duplicate_chat_success => 'Bate-papo duplicado';

  @override
  String get move_to_folder => 'Mover para pasta';

  @override
  String get remove_from_folder => 'Remover da pasta';

  @override
  String get create_folder => 'Criar pasta';

  @override
  String get new_folder => 'Nova pasta';

  @override
  String get folder_name_hint => 'Nome da pasta';

  @override
  String get all_chats => 'Todos';

  @override
  String get unfiled_chats => 'Não arquivado';

  @override
  String get create => 'Criar';

  @override
  String get server_path_prefix_label => 'Prefixo do caminho da API';

  @override
  String get server_path_prefix_hint => '/seu-token secreto';

  @override
  String get search_message_contents => 'Pesquisar conteúdo da mensagem';

  @override
  String get message_search_results => 'Correspondências de mensagens';

  @override
  String get saved_messages_title => 'Mensagens salvas';

  @override
  String get nav_saved_messages => 'Mensagens salvas';

  @override
  String get saved_messages_empty =>
      'Nenhuma mensagem salva ainda. Marque uma mensagem no menu de opções.';

  @override
  String get save_message => 'Salvar mensagem';

  @override
  String get message_saved => 'Mensagem salva';

  @override
  String token_count(int count) {
    return 'Tokens $count';
  }

  @override
  String estimated_token_count(int count) {
    return '~Tokens $count (estimado)';
  }

  @override
  String get test_tts_section_title => 'Teste de voz';

  @override
  String get test_tts_hint =>
      'Digite o texto para ouvir o mecanismo TTS atual…';

  @override
  String get test_speak_button => 'Fale';

  @override
  String get scroll_to_bottom => 'Role para baixo';

  @override
  String get generate_ai_response => 'Gerar resposta de IA';

  @override
  String get no_response => 'Sem resposta';

  @override
  String get export => 'Exportar';

  @override
  String get import => 'Importar';

  @override
  String get conversations_label => 'Conversas';

  @override
  String get personas_label => 'Personagens';

  @override
  String get settings_label => 'Configurações';

  @override
  String get export_conversation => 'Exportar conversa';

  @override
  String get tts_process_markdown => 'Remarcação de processo para fala';

  @override
  String get tts_process_markdown_desc =>
      'Remova a formatação como **negrito** antes de ler em voz alta';

  @override
  String get tts_skip_seconds => 'Pular intervalo';

  @override
  String get tts_skip_seconds_desc =>
      'Tamanho do salto para avançar e retroceder durante a reprodução';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}s';
  }

  @override
  String get preview_system_prompts => 'Visualizar prompts do sistema';

  @override
  String get welcome_message_1 => 'Em que posso ajudá-lo hoje?';

  @override
  String get welcome_message_2 =>
      'Pergunte-me qualquer coisa - estarei pronto quando você estiver.';

  @override
  String get welcome_message_3 =>
      'Seus dados são processados localmente e nunca saem do seu dispositivo.';

  @override
  String get welcome_message_4 =>
      'Precisa de ideias? Experimente uma das instruções rápidas.';

  @override
  String get temporary_chat => 'Bate-papo temporário';

  @override
  String get temporary_chat_desc =>
      'Os bate-papos não são salvos no histórico.';

  @override
  String get temporary_chat_banner =>
      'Bate-papo temporário – não salvo no histórico';

  @override
  String get temporary_chat_save_warning_title =>
      'Salvar mensagem no chat temporário?';

  @override
  String get temporary_chat_save_warning_body =>
      'Este chat é temporário e está oculto no histórico. A mensagem salva ainda aparecerá em Mensagens Salvas.';

  @override
  String get save_to_history => 'Salvar no histórico';

  @override
  String get share_conversation => 'Compartilhar conversa';

  @override
  String get download_tts_audio => 'Baixar áudio';

  @override
  String get tts_download_unavailable =>
      'O download está disponível apenas para Piper e Kitten TTS';

  @override
  String get tts_download_no_audio =>
      'Ainda não há áudio disponível para download';

  @override
  String get tts_download_success => 'Áudio salvo';

  @override
  String get return_to_chat => 'Voltar ao bate-papo';

  @override
  String get return_to_temp_chat => 'Retornar ao bate-papo temporário';

  @override
  String get insert_saved_message => 'Inserir mensagem salva';

  @override
  String get insert_saved_message_desc =>
      'Escolha uma mensagem salva para adicionar à sua entrada';

  @override
  String get model_info => 'Informações do modelo';

  @override
  String get model_name => 'Nome do modelo';

  @override
  String get model_identifier => 'Identificador';

  @override
  String get model_capabilities => 'Capacidades';

  @override
  String get model_api_pricing => 'Preços da API (por 1 milhão de tokens)';

  @override
  String get not_available => 'Não disponível';

  @override
  String get save_message_folders => 'Salvar mensagem';

  @override
  String get remove_from_saved => 'Remover dos salvos';

  @override
  String get message_already_saved => 'Salvo';

  @override
  String get stream_ttft => 'Hora do primeiro token';

  @override
  String get stream_tokens_per_sec => 'Tokens por segundo';

  @override
  String get stream_stop_reason => 'Pare a razão';

  @override
  String get stream_input_tokens => 'Tokens de entrada';

  @override
  String get stream_output_tokens => 'Tokens de saída';

  @override
  String get stream_generation_time => 'Tempo de geração';

  @override
  String get attach_image => 'Fotos';

  @override
  String get attach_text_document => 'Documentos';

  @override
  String get attach_shortcut_images => 'Fotos';

  @override
  String get attach_shortcut_documents => 'Arquivos';

  @override
  String get attach_shortcut_saved => 'Salvo';

  @override
  String get add_attachment => 'Adicionar anexo';

  @override
  String get add_to_chat => 'Adicionar ao bate-papo';

  @override
  String get choose_what_to_attach => 'O que você gostaria de adicionar?';

  @override
  String get choose_attachment_subtitle =>
      'Escolha uma fonte para anexar à sua mensagem';

  @override
  String get photo_permission_denied =>
      'O acesso à foto é necessário para anexar imagens';

  @override
  String get select_model_prompt => 'Selecione o modelo';

  @override
  String get characters_label => 'Personagens';

  @override
  String get exit_temporary_chat_title => 'Sair do bate-papo temporário?';

  @override
  String get exit_temporary_chat_body =>
      'Isso descartará o chat temporário atual e retornará para um novo chat.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Esta mensagem foi salva de um bate-papo temporário e não pode ser aberta na conversa original.';

  @override
  String get filter_title => 'Filtro';

  @override
  String get filter_pinned => 'Fixado';

  @override
  String get filter_archived => 'Arquivado';

  @override
  String get filter_temp_chats => 'Bate-papos temporários';

  @override
  String get filter_user_messages => 'Mensagens do usuário';

  @override
  String get filter_assistant_messages => 'Mensagens do assistente';

  @override
  String get archive_chat => 'Arquivo';

  @override
  String get unarchive_chat => 'Desarquivar';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensagens',
      one: '1 mensagem',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return 'Caracteres $count';
  }

  @override
  String get generate_title_with_ai => 'Gere com IA';

  @override
  String get generating_title => 'Gerando...';

  @override
  String get generate_title_failed => 'Não foi possível gerar um título';

  @override
  String get lm_studio_model_browser_title => 'Procure modelos';

  @override
  String get lm_studio_model_search_hint =>
      'Pesquise modelos por nome ou autor…';

  @override
  String get lm_studio_staff_picks => 'Escolhas da equipe';

  @override
  String get lm_studio_community_models => 'Modelos comunitários';

  @override
  String get lm_studio_no_models => 'Nenhum modelo encontrado';

  @override
  String lm_studio_models_count(int count) {
    return 'Modelos $count';
  }

  @override
  String get lm_studio_browse_models => 'Navegue e baixe';

  @override
  String get lm_studio_model_search => 'Pesquisa de modelo LMS';

  @override
  String get lm_studio_downloads_title => 'Transferências';

  @override
  String get lm_studio_choose_quant => 'Escolha uma opção de download';

  @override
  String get lm_studio_use_default_quant => 'Usar padrão';

  @override
  String get lm_studio_recommended => 'Recomendado';

  @override
  String get lm_studio_clear_downloads => 'Limpar concluído';

  @override
  String get lm_studio_no_downloads => 'Ainda não há downloads';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Os downloads são executados no host do LM Studio. Pausar, parar e excluir modelos devem ser feitos nesse computador – não neste aplicativo.';

  @override
  String get lm_studio_staff_pick => 'Escolha da equipe';

  @override
  String get lm_studio_params => 'PARÂMETROS';

  @override
  String get lm_studio_arch => 'ARCO';

  @override
  String get lm_studio_domain => 'DOMÍNIO';

  @override
  String get lm_studio_format => 'FORMATO';

  @override
  String get lm_studio_vision => 'Visão';

  @override
  String get lm_studio_tool_use => 'Uso de ferramentas';

  @override
  String get lm_studio_reasoning => 'Raciocínio';

  @override
  String get openrouter_pricing_free => 'Grátis';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Entrada $input / Saída $output por 1 milhão de tokens';
  }

  @override
  String get lm_studio_download_options => 'Opções de download';

  @override
  String get lm_studio_download => 'Baixar';

  @override
  String lm_studio_download_size(String size) {
    return 'Baixar$size';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Baixando $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'README não disponível para este modelo.';

  @override
  String get lm_studio_full_gpu_offload =>
      'Possível descarregamento total da GPU';

  @override
  String get lm_studio_partial_gpu_offload =>
      'Possível descarregamento parcial da GPU';

  @override
  String get lm_studio_likely_too_large => 'Provavelmente muito grande';

  @override
  String get lm_studio_available_ram_gb => 'RAM disponível (GB, opcional)';

  @override
  String get lm_studio_available_vram_gb => 'VRAM disponível (GB, opcional)';

  @override
  String get lm_studio_memory_settings_title => 'Memória para recomendações';

  @override
  String get lm_studio_memory_settings_desc =>
      'Usado para estimar se os modelos cabem na sua máquina no navegador de modelos.';

  @override
  String get think_button_label => 'Pense';

  @override
  String get thinking_mode_title => 'Modo de pensamento';

  @override
  String get reasoning_effort_low => 'Baixo';

  @override
  String get reasoning_effort_medium => 'Médio';

  @override
  String get reasoning_effort_high => 'Alto';

  @override
  String get reasoning_effort_minimal => 'Mínimo';

  @override
  String get reasoning_effort_xhigh => 'X-Alto';

  @override
  String get reasoning_effort_max => 'Máx.';

  @override
  String get reasoning_effort_off => 'Desligado';

  @override
  String get could_not_read_file => 'Não foi possível ler o arquivo';

  @override
  String get server_offline => 'Servidor off-line';

  @override
  String get could_not_establish_connection =>
      'Não foi possível estabelecer uma conexão com o servidor. Verifique se o seu servidor está funcionando e se as configurações de host/porta estão corretas.';

  @override
  String get retry_connection => 'Tentar novamente a conexão';

  @override
  String get tokens_label => 'Fichas';

  @override
  String get enter_context_length => 'Insira o comprimento do contexto...';

  @override
  String get openrouter_disclosure =>
      'Ao conectar este provedor, suas mensagens e entradas de chat serão enviadas para seus servidores. LocalMind não rastreia nem armazena suas conversas.';

  @override
  String get welcome_message_cloud =>
      'Suas mensagens são enviadas para seu provedor conectado.';

  @override
  String get privacy_policy => 'Política de Privacidade';

  @override
  String get cloud_sync => 'Sincronização em nuvem S3';

  @override
  String get cloud_sync_description =>
      'Sincronização criptografada de ponta a ponta com seu próprio servidor compatível com S3';

  @override
  String get cloud_sync_endpoint => 'URL do terminal';

  @override
  String get cloud_sync_bucket => 'Balde';

  @override
  String get cloud_sync_region => 'Região';

  @override
  String get cloud_sync_prefix => 'Prefixo';

  @override
  String get cloud_sync_access_key => 'ID da chave de acesso';

  @override
  String get cloud_sync_secret_key => 'Chave de acesso secreta';

  @override
  String get cloud_sync_session_token => 'Token de sessão (opcional)';

  @override
  String get cloud_sync_passphrase => 'Senha de criptografia';

  @override
  String get cloud_sync_confirm_passphrase => 'Confirmar senha';

  @override
  String get cloud_sync_path_style => 'Use endereçamento estilo caminho';

  @override
  String get cloud_sync_allow_http => 'Permitir HTTP inseguro';

  @override
  String get cloud_sync_http_warning =>
      'HTTP expõe metadados e credenciais de solicitação à rede. Use-o apenas para um servidor S3 local confiável.';

  @override
  String get cloud_sync_test => 'Conexão de teste';

  @override
  String get cloud_sync_enable => 'Ativar sincronização criptografada';

  @override
  String get cloud_sync_now => 'Sincronize agora';

  @override
  String get cloud_sync_disconnect => 'Desconecte este dispositivo';

  @override
  String get cloud_sync_last_synced => 'Última sincronização';

  @override
  String get cloud_sync_never => 'Nunca';

  @override
  String get cloud_sync_conflicts => 'Conflitos preservados';

  @override
  String get cloud_sync_passphrase_mismatch => 'As senhas não correspondem';

  @override
  String get crash_report_title => 'Algo deu errado';

  @override
  String get crash_report_stack_trace => 'Rastreamento de pilha';

  @override
  String get crash_report_tap_to_expand => 'Toque para expandir';

  @override
  String get crash_report_button => 'Denunciar esta falha';

  @override
  String get crash_try_again => 'Tente novamente';

  @override
  String get crash_report_empty_stack => '<vazio>';

  @override
  String get crash_report_disclaimer =>
      'Os relatórios abrem o GitHub com diagnósticos pré-preenchidos. Você permanece no controle — nada é enviado automaticamente. Revise e remova qualquer conteúdo sensível antes de enviar.';

  @override
  String get crash_report_copied => 'Copiado para a área de transferência';

  @override
  String get report_a_problem => 'Informar um problema';

  @override
  String get rename_folder => 'Renomear pasta';

  @override
  String get delete_folder => 'Excluir pasta';

  @override
  String get delete_folder_title => 'Excluir pasta?';

  @override
  String delete_folder_body(String name) {
    return 'Tem certeza de que deseja excluir \"$name\"? As conversas ou mensagens salvas serão movidas de volta para \"Não arquivadas\". Isto não pode ser desfeito.';
  }

  @override
  String get folder_name_required => 'Por favor insira um nome de pasta';

  @override
  String get model_required_toast =>
      'Você precisa selecionar um modelo primeiro';

  @override
  String get settings_concise_voice_responses =>
      'Respostas concisas no modo de voz';

  @override
  String get settings_concise_voice_responses_desc =>
      'Mantenha as respostas do LLM breves (1 parágrafo curto) e faça perguntas de acompanhamento em modo de voz.';

  @override
  String get s3_connection_succeeded => 'Conexão S3 bem-sucedida.';

  @override
  String failed_to_open_url(String error) {
    return 'Falha ao abrir URL: $error';
  }

  @override
  String failed_to_copy(String error) {
    return 'Falha ao copiar: $error';
  }

  @override
  String get file_explorer_not_found =>
      'Nenhum explorador de arquivos encontrado. Certifique-se de que um aplicativo gerenciador de arquivos esteja instalado e ativado em seu dispositivo.';

  @override
  String export_data_failed(String error) {
    return 'Falha ao exportar backup: $error';
  }

  @override
  String file_pick_failed(String error) {
    return 'Falha ao selecionar arquivo: $error';
  }

  @override
  String image_pick_failed(String error) {
    return 'Falha ao selecionar imagem: $error';
  }

  @override
  String get calendar_access => 'Acesso ao calendário';

  @override
  String get calendar_access_desc =>
      'Permitir que a IA leia e crie eventos de calendário';

  @override
  String get calendar_permission_denied =>
      'Permissão de calendário negada. Conceda acesso ao calendário nas configurações do seu dispositivo.';

  @override
  String get location_access => 'Acesso à localização';

  @override
  String get location_access_desc =>
      'Permitir que a IA obtenha sua localização atual com o nome do lugar';

  @override
  String get location_permission_denied =>
      'Permissão de localização negada. Conceda acesso à localização nas configurações do seu dispositivo.';

  @override
  String get builtin_ai_not_supported =>
      'A IA integrada não é compatível com este dispositivo.';

  @override
  String get builtin_ai_unsupported_desc =>
      'O hardware ou sistema operacional do seu dispositivo não oferece suporte à IA do sistema no dispositivo (por exemplo, Gemini Nano/Apple Intelligence). Escolha um modelo para download.';

  @override
  String get builtin_ai_unsupported_chip => 'Não compatível';

  @override
  String get builtin_ai_enable => 'Habilitar';
}
