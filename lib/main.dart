import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'firebase_options.dart';
import 'ndef_record_info.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('es')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: 'Data Management',
      initialRoute: '/',
      routes: {
        '/': (context) => const SecondScreen(),
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
      final documentId = prefs.getString('documentId');

      DocumentReference docRef;
      if (documentId != null) {
        docRef = FirebaseFirestore.instance
            .collection('Senior Data')
            .doc(documentId);
        await docRef.update(enrichedData);
      } else {
        docRef = await FirebaseFirestore.instance
            .collection('Senior Data')
            .add(enrichedData);
        prefs.setString('documentId', docRef.id);
      }

      String documentUrl =
          'https://vayala-04.github.io/Varsha_url_qr-code/?id=${docRef.id}';
      prefs.setString('url', documentUrl);

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

    final result = await Navigator.pushNamed(
      context,
      '/second/form',
      arguments: latestData,
    ) as Map<String, String>?;

    if (result != null) {
      prefs.setString('latest_submission', jsonEncode(result));
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
              style: ElevatedButton.styleFrom(
                fixedSize: const Size(200, 50),
              ),
              child: const Text('Write to Pendant'),
              onPressed: () {
                _handleWriteToPendant(context);
              },
            ),
            /*const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                fixedSize: const Size(200, 50),
              ),
            // child: const Text('Read from Pendant'),
             //onPressed: () async {
              // await isNfcAvailable().then((available) {
               //  if (available) {
                 //  readNfcTag(context);
                 // } else {
                   // ScaffoldMessenger.of(context).showSnackBar(
                     // const SnackBar(
                       //  content: Text(
                         //    'NFC may not be supported or may be temporarily turned off.')),
                    //);
                 // }
                //});
              //},
            //),*/
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                fixedSize: const Size(200, 50),
              ),
              child: const Text('View Summary'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                String? url = prefs.getString('url');

                if (url != null) {
                  debugPrint("url $url");
                  Uri uri = Uri.parse(url);
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
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No submissions available to display!')),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                fixedSize: const Size(200, 50),
              ),
              child: const Text('Delete Data'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                String? url = prefs.getString('url');

                if (url != null) {
                  Uri uri = Uri.parse(url);
                  final documentId = uri.queryParameters['id'] ?? '';

                  await FirebaseFirestore.instance
                      .collection('Senior Data')
                      .doc(documentId)
                      .delete()
                      .then((_) async {
                    var pref = await SharedPreferences.getInstance();
                    pref.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Data Deleted Successfully')),
                    );
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No Data')),
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

  Future<void> readNfcTag(BuildContext context) async {
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
          .collection('Senior Data')
          .doc(documentId)
          .get();

      if (docSnapshot.exists) {
        final fields = docSnapshot.data();

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
          const SnackBar(content: Text('No data found in the document')),
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

class SimplifiedDataScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  final String documentUrl;

  const SimplifiedDataScreen(
      {super.key, required this.data, required this.documentUrl});

  @override
  SimplifiedDataScreenState createState() => SimplifiedDataScreenState();
}

class SimplifiedDataScreenState extends State<SimplifiedDataScreen> {
  List<String> languages = ['English', 'Spanish'];

  final List<String> fieldNames = [
    'full_name',
    'date_of_birth',
    'phone_number',
    'address',
    'preferred_language',
    'preferred_hospital',
    'primary_contact_name',
    'relationship_to_primary_contact',
    'primary_contact_phone',
    'allergies',
    'medications',
    'pre_existing_conditions',
    'past_surgeries',
    'do_not_resuscitate',
    'blood_type',
    'primary_physician_name',
    'primary_physician_phone',
    'insurance_provider',
    'policy_number',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Senior Data'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('select_language'.tr()),
            DropdownButton(
              isExpanded: true,
              value: context.locale == const Locale('en')
                  ? languages[0]
                  : languages[1],
              onChanged: (value) {
                if (value == 'English') {
                  context.setLocale(const Locale('en'));
                } else if (value == 'Spanish') {
                  context.setLocale(const Locale('es'));
                }
              },
              items: languages.map((String lang) {
                return DropdownMenuItem<String>(
                  value: lang,
                  child: Text(lang),
                );
              }).toList(),
            ),
            (widget.data['profile'] != null &&
                    widget.data['profile'].isNotEmpty)
                ? Center(
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 0),
                          shape: BoxShape.circle,
                          color: Colors.grey,
                          image: DecorationImage(
                              image: CachedNetworkImageProvider(
                                  widget.data['profile']))),
                      height: 100,
                      width: 100,
                    ),
                  )
                : const SizedBox(),
            const SizedBox(
              height: 16,
            ),
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: fieldNames.map((entry) {
                return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          '${entry.tr()}:   ${widget.data[entry]??'N/A'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      );
              }).toList(),
            ),
            (widget.data['pdf'] != null && widget.data['pdf'].isNotEmpty)
                ? Center(
                    child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) =>
                                  PdfPreview(widget.data['pdf'])));
                        },
                        child: const Text("View PDF")),
                  )
                : const SizedBox(),
            const SizedBox(
              height: 16,
            ),
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

class PdfPreview extends StatefulWidget {
  final String url;

  const PdfPreview(this.url, {super.key});

  @override
  PdfPreviewState createState() => PdfPreviewState();
}

class PdfPreviewState extends State<PdfPreview> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Preview'),
      ),
      body: const PDF(
        swipeHorizontal: true,
      ).cachedFromUrl(widget.url),
    );
  }
}

class FormScreenState extends State<FormScreen> {
  final Map<String, TextEditingController> _controllers = {};
  Map<String, dynamic>? latestSubmission;
  final List<String> _fieldNames = [
    'full_name',
    'date_of_birth',
    'phone_number',
    'address',
    'preferred_language',
    'preferred_hospital',
    'primary_contact_name',
    'relationship_to_primary_contact',
    'primary_contact_phone',
    'allergies',
    'medications',
    'pre_existing_conditions',
    'past_surgeries',
    'do_not_resuscitate',
    'blood_type',
    'primary_physician_name',
    'primary_physician_phone',
    'insurance_provider',
    'policy_number',
  ];

  List<String> languages = ['English', 'Spanish'];

  File? selectedProfile;
  File? selectedPdf;


  bool loader = false;

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
        title: const Text('Data Portal'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('select_language'.tr()),
            DropdownButton(
              isExpanded: true,
              value: context.locale == const Locale('en')
                  ? languages[0]
                  : languages[1],
              onChanged: (value) {
                if (value == 'English') {
                  context.setLocale(const Locale('en'));
                } else if (value == 'Spanish') {
                  context.setLocale(const Locale('es'));
                }
              },
              items: languages.map((String lang) {
                return DropdownMenuItem<String>(
                  value: lang,
                  child: Text(lang),
                );
              }).toList(),
            ),
            const SizedBox(
              height: 16,
            ),
            Center(
                child: Stack(
              children: [
                (selectedProfile == null && (args?['profile'] == null||args?['profile'].isEmpty))
                    ? Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 0),
                            shape: BoxShape.circle,
                            color: Colors.grey,
                            image: const DecorationImage(
                                image: AssetImage('assets/icons/avatar.png'))),
                        height: 100,
                        width: 100,
                      )
                    : (selectedProfile != null)
                        ? Container(
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.white, width: 0),
                                shape: BoxShape.circle,
                                color: Colors.grey,
                                image: DecorationImage(
                                    image: FileImage(selectedProfile!))),
                            height: 100,
                            width: 100,
                          )
                        : Container(
                            decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colors.white, width: 0),
                                shape: BoxShape.circle,
                                color: Colors.grey,
                                image: DecorationImage(
                                    image: CachedNetworkImageProvider(
                                        args?['profile']))),
                            height: 100,
                            width: 100,
                          ),
                Positioned(
                  bottom: 2,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {
                      showPicker(context, 0);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        color: Colors.black,
                      ),
                      height: 28,
                      width: 28,
                      child: const Icon(
                        Icons.edit,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )),
            const SizedBox(
              height: 16,
            ),
            for (final field in _fieldNames) ...[
              TextField(
                controller: _controllers[field],
                decoration: InputDecoration(labelText: field.tr()),
              ),
              const SizedBox(height: 16),
              field == 'do_not_resuscitate'
                  ? Center(
                      child: TextButton(
                        onPressed: pickPdfFile,
                        child: Text((selectedPdf == null&& (args?['pdf']==null||args?['pdf'].isEmpty))
                            ? "select_pdf".tr()
                            : 'file_selected'.tr()),
                      ),
                    )
                  : const SizedBox(),
            ],
            const SizedBox(
              height: 24,
            ),
            Center(
              child: loader
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  fixedSize: const Size(200, 50),
                ),
                      onPressed: () => _handleSubmit(context, args),
                      child: Text('submit'.tr()),
                    ),
            ),
            const SizedBox(
              height: 24,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit(
      BuildContext context, Map<String, dynamic>? args) async {
    setState(() {
      loader = true;
    });

    String profileUrl = '';
    String pdfUrl = '';

    if (selectedProfile != null) {
      profileUrl = await uploadImage(context, selectedProfile, 0) ?? '';
    } else {
      profileUrl = args?['profile'] ?? '';
    }

    if (selectedPdf != null) {
      pdfUrl = await uploadImage(context, selectedPdf, 1) ?? '';
    } else {
      pdfUrl = args?['pdf'] ?? '';
    }

    final submission = {
      for (final field in _fieldNames)
        if (_controllers[field]!.text.trim().isNotEmpty)
          field: _controllers[field]!.text.trim(),
      'profile': profileUrl,
      'pdf': pdfUrl
    };

    setState(() {
      loader = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('from_submitted_successfully'.tr())),
    );

    Navigator.pop(context, submission);
  }

  void showPicker(BuildContext context, int type) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext bc) {
          return SafeArea(
            child: Wrap(
              children: <Widget>[
                ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: Text('photo_library'.tr()),
                    onTap: () {
                      _imgFromGallery(context, type);
                      Navigator.of(context).pop();
                    }),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text('camera'.tr()),
                  onTap: () {
                    _imgFromCamera(context, type);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        });
  }

  Future<void> _imgFromGallery(BuildContext context, int type) async {
    final ImagePicker picker = ImagePicker();
    // Pick an image
    await picker
        .pickImage(
            source: ImageSource.gallery,
            maxHeight: 1080,
            maxWidth: 1080,
            imageQuality: 90)
        .then((image) async {
      if (image?.path != null) {
        setState(() {
          selectedProfile = File(image!.path);
        });
      }
    });
  }

  Future<void> _imgFromCamera(BuildContext context, int type) async {
    final ImagePicker picker = ImagePicker();
    // Capture a photo
    await picker
        .pickImage(
            source: ImageSource.camera,
            maxHeight: 1080,
            maxWidth: 1080,
            imageQuality: 90)
        .then((image) async {
      if (image?.path != null) {
        setState(() {
          selectedProfile = File(image!.path);
        });
      }
    });
  }

  Future<String?> uploadImage(
      BuildContext context, File? file, int type) async {
    String fileName = basename(file!.path);
    try {
      await firebase_storage.FirebaseStorage.instance
          .ref('${type == 0 ? 'images' : 'files'}/$fileName')
          .putFile(File(file.path));
      var downloadUrl = await firebase_storage.FirebaseStorage.instance
          .ref('${type == 0 ? 'images' : 'files'}/$fileName')
          .getDownloadURL();
      return downloadUrl;
    } on firebase_storage.FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message.toString())),
      );
      debugPrint("Upload Error ${e.message}");
    }
    return null;
  }

  Future<void> pickPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      String filePath = result.files.single.path!;
      setState(() {
        selectedPdf = File(filePath);
      });
    }
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
