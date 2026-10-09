import 'package:flutter/material.dart';
import 'package:takeed/takeed.dart';

/// Minimal app showing the Takeed calls. Set your App ID and server below.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Takeed.initialize(
    const String.fromEnvironment('TAKEED_APP_ID', defaultValue: '00000000-0000-0000-0000-000000000000'),
    apiUrl: const String.fromEnvironment('TAKEED_API_URL', defaultValue: 'https://takeed.example.com'),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  String _last = 'No notification opened yet';

  @override
  void initState() {
    super.initState();
    Takeed.Notifications.addClickListener((event) {
      setState(() => _last = 'Opened ${event.notification.notificationId} (button: ${event.result.actionId ?? '-'})');
    });
    Takeed.Notifications.addForegroundWillDisplayListener((event) => event.display());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Takeed example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                  onPressed: () => Takeed.Notifications.requestPermission(true),
                  child: const Text('Allow notifications')),
              ElevatedButton(onPressed: () => Takeed.login('demo-user'), child: const Text('Log in as demo-user')),
              ElevatedButton(
                  onPressed: () => Takeed.User.addTagWithKey('plan', 'gold'), child: const Text('Tag plan=gold')),
              const ElevatedButton(onPressed: Takeed.logout, child: Text('Log out')),
              const SizedBox(height: 24),
              Text(_last),
              Text('Subscription: ${Takeed.User.pushSubscription.id ?? '-'}'),
            ],
          ),
        ),
      ),
    );
  }
}
