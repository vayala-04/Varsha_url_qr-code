import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'ndef_record_info.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patient Data Management',
      initialRoute: '/',
      routes: {
        '/': (context) => const SecondScreen(),
        // Set SecondScreen as the home page
        '/second/form': (context) => const FormScreen(),
        '/summary': (context) => const SummaryScreen(),
      },
    );
  }
}

class SecondScreen extends StatefulWidget {
  const SecondScreen({super.key});

  @override
  SecondScreenState createState() => SecondScreenState();
}

class SecondScreenState extends State<SecondScreen> {
  Map<String, dynamic>? latestSubmission;

  Future<String?> saveToFireStore(Map<String, String> data) async {
    try {
      final enrichedData = {
        ...data,
        'timestamp': FieldValue.serverTimestamp(),
      };

      final prefs = await SharedPreferences.getInstance();
      final documentId = prefs.getString('documentId'); // Retrieve the stored document ID

      DocumentReference docRef;
      if (documentId != null) {
        // Update the existing document
        docRef = FirebaseFirestore.instance.collection('Patient Data').doc(documentId);
        await docRef.update(enrichedData);
      } else {
        // Create a new document if no document ID exists
        docRef = await FirebaseFirestore.instance.collection('Patient Data').add(enrichedData);

        // Store the document ID for future updates
        prefs.setString('documentId', docRef.id);
      }

      String documentUrl =
          'https://vayala-04.github.io/Varsha_url_qr-code/?id=${docRef.id}';
      prefs.setString('url', documentUrl); // Store the document URL

      return documentUrl;
    } catch (e) {
      print('Failed to save or update data: $e');
      return null;
    }
  }

  void _handleWriteToPendant(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? latestData;
    if (prefs.getString('latest_submission') != null) {
      latestData = jsonDecode(prefs.getString('latest_submission')!);
    }
    final result = await Navigator.pushNamed(context, '/second/form',
        arguments: latestData) as Map<String, String>?;

    if (result != null) {
      String? documentUrl = await saveToFireStore(result);

      if (documentUrl != null) {
        NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
          try {
            var ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tag is not writable')),
              );
              NfcManager.instance.stopSession();
              return;
            }

            NdefMessage message = NdefMessage([
              NdefRecord.createUri(Uri.parse(documentUrl)),
            ]);

            await ndef.write(message);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('URL written to NFC tag successfully!')),
            );

            NfcManager.instance.stopSession();
          } catch (e) {
            print('Error writing to NFC tag: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to write to NFC tag: $e')),
            );
            NfcManager.instance.stopSession();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save data or generate URL')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to RAPIDx'),
      ),
      body: Center(
        child: Column(
          children: [
            ElevatedButton(
              child: const Text('Write to Pendant'),
              onPressed: () {
                _handleWriteToPendant(context);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              child: const Text('Read from Pendant'),
              onPressed: () async {
                await isNfcAvailable().then((available) {
                  if (available) {
                    readNfcTag();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'NFC may not be supported or may be temporarily turned off.')),
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              child: const Text('View Summary'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                String? url = prefs.getString('url');

                if (url != null) {
                  Uri uri = Uri.parse(url);
                  // Get the value of the 'id' parameter
                  final documentId = uri.queryParameters['id'] ?? '';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UrlListScreen(
                        documentUrl: url,
                        documentId: documentId,
                        from: 'viewSummary',
                      ),
                    ),
                  );

                  /* Navigator.pushNamed(
                    context,
                    '/summary',
                    arguments: _latestSubmission,
                  );*/
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No submissions available to display!')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> isNfcAvailable() async =>
      await NfcManager.instance.isAvailable().then((isAvailable) async {
        return isAvailable;
      });

  Future<void> readNfcTag() async {
    if (Platform.isIOS) {
      return NfcManager.instance.startSession(
        alertMessage: "Hold your phone near the NFC device",
        onDiscovered: (tag) async {
          try {
            Ndef? tech = Ndef.from(tag);
            if (tech == null || !tech.isWritable) {
              await NfcManager.instance.stopSession();
              const SnackBar(content: Text('Tag is not compatible with NDEF'));
              return;
            } else {
              final cachedMessage = tech.cachedMessage;
              final record = cachedMessage?.records[0];
              final info = NdefRecordInfo.fromNdef(record);
              debugPrint("uri ${info.title}");
              debugPrint("uri ${info.subtitle}");
              await NfcManager.instance.stopSession().then((_) async {
                if (info.title == 'Wellknown Uri') {
                  try {
                    Uri uri = Uri.parse(info.subtitle);

                    final documentId = uri.queryParameters['id'] ?? '';
                    final prefs = await SharedPreferences.getInstance();
                    prefs.setString('url', info.subtitle);

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UrlListScreen(
                          documentUrl: info.subtitle,
                          documentId: documentId,
                          from: 'read',
                        ),
                      ),
                    );
                  } on Exception catch (e) {
                    SnackBar(content: Text("Exception ${e.toString()}"));
                  }
                } else {
                  await NfcManager.instance
                      .stopSession(errorMessage: 'Invalid data format');
                }
              });
            }
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessage: '$e');
          }
        },
      );
    }
  }
}

class UrlListScreen extends StatelessWidget {
  final String documentUrl;
  final String documentId;
  final String from;

  const UrlListScreen(
      {super.key,
      required this.documentUrl,
      required this.documentId,
      required this.from});

  void _fetchSimplifiedData(BuildContext context) async {
    debugPrint("DOC ID $documentId");
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('Patient Data')
          .doc(documentId)
          .get();

      if (docSnapshot.exists) {
        final fields = docSnapshot.data();

        // Simplify the fields data
        final simplifiedData = fields?.map((key, value) {
          if (value is Map && value.containsKey('stringValue')) {
            return MapEntry(key, value['stringValue']);
          }
          return MapEntry(key, value.toString());
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SimplifiedDataScreen(
                data: simplifiedData!, documentUrl: documentUrl),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No data found in the document')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document URL'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Document URL:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _fetchSimplifiedData(context),
              child: Text(
                documentUrl,
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            from == 'read'
                ? const SizedBox()
                : QrImageView(
                    data: documentUrl,
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
          ],
        ),
      ),
    );
  }
}

class SimplifiedDataScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String documentUrl;

  const SimplifiedDataScreen(
      {super.key, required this.data, required this.documentUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListView(
              shrinkWrap: true,
              children: data.entries.map((entry) {
                return entry.key == 'timestamp'
                    ? const SizedBox()
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          '${entry.key}:   ${entry.value}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      );
              }).toList(),
            ),
            /*const SizedBox(
              height: 10,
            ),
            QrImageView(
              data: documentUrl,
              version: QrVersions.auto,
              size: 200.0,
            ),*/
          ],
        ),
      ),
    );
  }
}

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  FormScreenState createState() => FormScreenState();
}

class FormScreenState extends State<FormScreen> {
  final Map<String, TextEditingController> _controllers = {};
  Map<String, dynamic>? latestSubmission;
  final List<String> _fieldNames = [
    'Full Name',
    'Date of Birth',
    'Phone Number',
    'Address',
    'Preferred Language',
    'Preferred Hospital',
    'Primary Contact Name',
    'Relationship to Primary Contact',
    'Primary Contact Phone',
    'Allergies',
    'Medications',
    'Pre-Existing Conditions',
    'Past Surgeries',
    'Do Not Resuscitate',
    'Blood Type',
    'Primary Physician Name',
    'Primary Physician Phone',
    'Insurance Provider',
    'Policy Number',
  ];

  @override
  void initState() {
    super.initState();

    for (final field in _fieldNames) {
      _controllers[field] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleSubmit() {
    final submission = {
      for (final field in _fieldNames)
        if (_controllers[field]!.text.trim().isNotEmpty)
          field: _controllers[field]!.text.trim(),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form Submitted Successfully!')),
    );

    Navigator.pop(context, submission);
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args != null) {
      for (final field in _fieldNames) {
        _controllers[field]?.text = args[field] ?? '';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Data Portal'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final field in _fieldNames) ...[
              TextField(
                controller: _controllers[field],
                decoration: InputDecoration(labelText: field),
              ),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: _handleSubmit,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, String> data =
        ModalRoute.of(context)?.settings.arguments as Map<String, String>;

    bool hasValue(String value) => value.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in data.entries) ...[
              if (hasValue(entry.value))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
