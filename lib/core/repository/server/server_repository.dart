import '../../../features/models/data/models/model_info.dart';
import '../../../features/servers/data/models/server.dart';

abstract class ServerRepository {
  Future<bool> testConnection(Server server);
  Future<List<ModelInfo>> fetchModels(Server server);
  Future<bool> pingServer(Server server);
  List<Server> getServers();
  Future<Server> addServer(Server server);
  Future<void> updateServer(Server server);
  Future<void> deleteServer(String id);
  Server? getServerById(String id);
  Server? getDefaultServer();
  Future<void> setDefaultServer(String id);
}
