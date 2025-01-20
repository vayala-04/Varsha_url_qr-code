import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

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
        '/second/form': (context) => const FormScreen(),
      },
    );
  }
}

class SecondScreen extends StatelessWidget {
  const SecondScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select an Option'),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('Fill Form'),
          onPressed: () {
            Navigator.pushNamed(context, '/second/form');
          },
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
  File? _selectedProfileImage; // To store the selected profile image
  File? _selectedPdfFile; // To store the selected PDF file
  final ImagePicker _picker = ImagePicker(); // Initialize ImagePicker

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

  Future<void> _pickProfileImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      maxHeight: 1000,
      maxWidth: 1000,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedProfileImage = File(pickedFile.path);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image selected')),
      );
    }
  }

  Future<void> _pickPdfFile() async {
    final result = await _picker.pickImage(source: ImageSource.gallery);

    if (result != null && result.path.endsWith('.pdf')) {
      setState(() {
        _selectedPdfFile = File(result.path);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid PDF file')),
      );
    }
  }

  void _handleSubmit() {
    final submission = {
      for (final field in _fieldNames)
        if (_controllers[field]!.text.trim().isNotEmpty)
          field: _controllers[field]!.text.trim(),
    };

    // Add profile picture and PDF info to submission if available
    if (_selectedProfileImage != null) {
      submission['ProfilePicturePath'] = _selectedProfileImage!.path;
    }
    if (_selectedPdfFile != null) {
      submission['PdfFilePath'] = _selectedPdfFile!.path;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Form Submitted Successfully!')),
    );

    Navigator.pop(context, submission);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Data Portal'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile Picture',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickProfileImage,
              child: _selectedProfileImage == null
                  ? Container(
                      width: 100,
                      height: 100,
                      color: Colors.grey[300],
                      child: const Center(child: Text('Upload Image')),
                    )
                  : Image.file(
                      _selectedProfileImage!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 20),
            for (final field in _fieldNames) ...[ // Add all other fields
              TextField(
                controller: _controllers[field],
                decoration: InputDecoration(labelText: field),
              ),
              if (field == 'Do Not Resuscitate') ...[ // Add PDF upload after this field
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _pickPdfFile,
                  child: const Text('Upload PDF Document'),
                ),
                const SizedBox(height: 20),
              ],
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
