// ============================================================
//  Smart Drainage Guard - community app settings (TEMPLATE)
//
//  Copy this file to lib/config.dart and fill in your own values.
//  lib/config.dart is listed in .gitignore, so it is never uploaded.
//
//  In EMQX (Access Control -> Authorization) give the community user:
//    allow publish   sdg/report/#
//    allow subscribe sdg/report/#  and  sdg/status/#
//    deny  publish   sdg/status/#   (only workers can mark jobs done)
// ============================================================

class AppConfig {
  /// Broker address, e.g. EMQX Cloud -> Deployment -> Overview -> "Address"
  static const String brokerHost = 'your-broker-host.emqxsl.com';

  /// TLS port for apps and devices (the website uses 8084 for WebSocket)
  static const int brokerPort = 8883;

  /// Shared, limited community login (residents never see or type this)
  static const String brokerUser = 'sdg-community';
  static const String brokerPassword = 'YOUR_COMMUNITY_PASSWORD';

  /// Topics - must match community.html, dashboard.html and the sensor node
  static const String reportTopicPrefix = 'sdg/report/';
  static const String reportTopicFilter = 'sdg/report/#';
  static const String statusTopicFilter = 'sdg/status/#'; // written by workers' dashboard only
}
