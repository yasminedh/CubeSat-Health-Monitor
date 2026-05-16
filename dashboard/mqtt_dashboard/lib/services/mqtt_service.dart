import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {

  late MqttServerClient client;

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {

    client = MqttServerClient(
      host,
      'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
    );

    client.port = port;
    client.secure = true;
    client.keepAlivePeriod = 20;

    client.connectionMessage = MqttConnectMessage()
        .authenticateAs(username, password)
        .startClean();

    await client.connect();
  }

  void subscribe(String topic) {
    client.subscribe(topic, MqttQos.atMostOnce);
  }

  void publish(String topic, String payload) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client.publishMessage(
      topic,
      MqttQos.atMostOnce,
      builder.payload!,
    );
  }
}