import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_recognitions/camera_screen.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  _FaceVerificationScreenState createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? cameraController;
  late FaceDetector faceDetector;
  bool isProcessing = false;
  List<double>? sampleFaceEmbeddings;
  XFile? _capturedImageFile;

  @override
  void initState() {
    super.initState();
    _loadSampleFaceEmbeddings();
  }

  @override
  void dispose() {
    cameraController?.dispose();
    faceDetector.close();
    super.dispose();
  }

  Future<File?> _saveImageToTempDirectory(img.Image image) async {
    try {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/temp_image.jpg';
      final imageBytes = Uint8List.fromList(img.encodeJpg(image));
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      return file;
    } catch (e) {
      if (kDebugMode) {
        print('Error saving image to temp directory: $e');
      }
      return null;
    }
  }

  Future<void> _loadSampleFaceEmbeddings() async {
    final sampleImage = await _loadSampleImage();
    if (sampleImage != null) {
      final tempFile = await _saveImageToTempDirectory(sampleImage);
      if (tempFile != null) {
        final inputImage = InputImage.fromFilePath(tempFile.path);
        final faceDetector = GoogleMlKit.vision.faceDetector(FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          enableClassification: true,
        ));

        try {
          final sampleFaces = await faceDetector.processImage(inputImage);
          if (sampleFaces.isNotEmpty) {
              print('Sample faces detected: ${sampleFaces.length}');
            // Crop the face from the sample image
            final face = sampleFaces.first;
            final boundingBox = face.boundingBox;

            final croppedSampleFaceImage = img.copyCrop(
              sampleImage,
              boundingBox.left.toInt(),
              boundingBox.top.toInt(),
              boundingBox.width.toInt(),
              boundingBox.height.toInt(),
            );

            // Save cropped face image to a temp file (optional, if you want to visualize it)
            final croppedTempFile = await _saveImageToTempDirectory(croppedSampleFaceImage);

            // Extract face embeddings from the cropped sample face image
            if (croppedTempFile != null) {
              final croppedInputImage = InputImage.fromFilePath(croppedTempFile.path);
              final croppedSampleFaces = await faceDetector.processImage(croppedInputImage);

              if (croppedSampleFaces.isNotEmpty) {
                sampleFaceEmbeddings = _extractFaceEmbeddings(croppedSampleFaces.first);
                debugPrint('Sample face embeddings: $sampleFaceEmbeddings');
              }
            }
          } else {
            print('No face detected in sample image.');
          }
        } catch (e) {
          print('Error processing sample image: $e');
        }
      }
    }
  }

  Future<img.Image?> _loadSampleImage() async {
    final ByteData data = await rootBundle.load('assets/shilpa_photo.jpeg');
    final buffer = data.buffer;
    final bytes = buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return img.decodeImage(bytes);
  }

  Future<void> _captureImage() async {
    final image = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraPage()), // Your camera screen widget
    );
    if (image != null) {
      setState(() {
        _capturedImageFile = image;
      });
    }
  }

  Future<void> _verifyImage() async {
    if (_capturedImageFile == null) {
      _showAlert('No image captured', 'Please capture an image first.');
      return;
    }

    if (isProcessing) return;
    isProcessing = true;

    if (_capturedImageFile!.path.isNotEmpty) {
      final capturedImage = img.decodeImage(File(_capturedImageFile!.path).readAsBytesSync());
      if (capturedImage != null) {
        final inputImage = InputImage.fromFilePath(_capturedImageFile!.path);
        final faceDetector = GoogleMlKit.vision.faceDetector(FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          enableClassification: true,
        ));

        final capturedFaces = await faceDetector.processImage(inputImage);

        if (capturedFaces.isNotEmpty) {
          // Crop the face from the image
          final face = capturedFaces.first;
          final boundingBox = face.boundingBox;

          final croppedFaceImage = img.copyCrop(
            capturedImage,
            boundingBox.left.toInt(),
            boundingBox.top.toInt(),
            boundingBox.width.toInt(),
            boundingBox.height.toInt(),
          );

          // Save cropped face image to a temp file (optional, if you want to visualize it)
          final tempFile = await _saveImageToTempDirectory(croppedFaceImage);

          // Verify the cropped face
          final croppedInputImage = InputImage.fromFilePath(tempFile?.path ?? _capturedImageFile!.path);
          final faceDetectorCropped = GoogleMlKit.vision.faceDetector(FaceDetectorOptions(
            enableLandmarks: true,
            enableContours: true,
            enableClassification: true,
          ));

          final croppedFaces = await faceDetectorCropped.processImage(croppedInputImage);

          if (croppedFaces.isNotEmpty) {
            final capturedFaceEmbeddings = _extractFaceEmbeddings(croppedFaces.first);
            print(capturedFaceEmbeddings);
            if (sampleFaceEmbeddings != null) {
              final similarity = _calculateCosineSimilarity(sampleFaceEmbeddings!, capturedFaceEmbeddings);
              print('Similarity: $similarity');
              bool isMatch = similarity > 0.75; // Adjust this threshold based on testing and requirements

              if (isMatch) {
                _showVerificationResult('Faces Match!');
              } else {
                _showVerificationResult('Faces Do Not Match!');
              }
            }
          } else {
            _showAlert('No face detected in cropped image', 'No face detected in the cropped face image.');
          }
        } else {
          _showAlert('No face detected', 'No face detected in the captured image.');
        }
      }
    }

    isProcessing = false;
  }

  List<double> _extractFaceEmbeddings(Face face) {
    try {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
      final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

      print('Left Eye: $leftEye');
      print('Right Eye: $rightEye');
      print('Nose Base: $noseBase');
      print('Left Mouth: $leftMouth');
      print('Right Mouth: $rightMouth');

      if (leftEye != null && rightEye != null && noseBase != null && leftMouth != null && rightMouth != null) {
        return [
          leftEye.x.toDouble(),
          leftEye.y.toDouble(),
          rightEye.x.toDouble(),
          rightEye.y.toDouble(),
          noseBase.x.toDouble(),
          noseBase.y.toDouble(),
          leftMouth.x.toDouble(),
          leftMouth.y.toDouble(),
          rightMouth.x.toDouble(),
          rightMouth.y.toDouble(),
        ];
      }

      print('Insufficient landmarks found.');
      return [];
    } catch (e) {
      print('Error extracting face embeddings: $e');
      return [];
    }
  }


  List<double> _normalizeLandmarks(List<double> landmarks) {
    double minX = landmarks[0];
    double maxX = landmarks[0];
    double minY = landmarks[1];
    double maxY = landmarks[1];

    for (int i = 0; i < landmarks.length; i += 2) {
      minX = min(minX, landmarks[i]);
      maxX = max(maxX, landmarks[i]);
      minY = min(minY, landmarks[i + 1]);
      maxY = max(maxY, landmarks[i + 1]);
    }

    double width = maxX - minX;
    double height = maxY - minY;

    List<double> normalizedLandmarks = [];
    for (int i = 0; i < landmarks.length; i += 2) {
      normalizedLandmarks.add((landmarks[i] - minX) / width);
      normalizedLandmarks.add((landmarks[i + 1] - minY) / height);
    }

    return normalizedLandmarks;
  }

  double _calculateCosineSimilarity(List<double> vectorA, List<double> vectorB) {
    if (vectorA.length != vectorB.length) {
      throw ArgumentError("Vectors must be of the same length");
    }
    // Normalize landmarks
    vectorA = _normalizeLandmarks(vectorA);
    vectorB = _normalizeLandmarks(vectorB);

    double dotProduct = 0.0;
    double magnitudeA = 0.0;
    double magnitudeB = 0.0;

    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      magnitudeA += vectorA[i] * vectorA[i];
      magnitudeB += vectorB[i] * vectorB[i];
    }

    magnitudeA = sqrt(magnitudeA);
    magnitudeB = sqrt(magnitudeB);

    if (magnitudeA == 0 || magnitudeB == 0) return 0.0;

    return dotProduct / (magnitudeA * magnitudeB);
  }

  void _showVerificationResult(String message) {
    _showAlert("Verification Result", message);
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _capturedImageFile != null
              ? SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: 300,
                  child: Image.file(
                    File(_capturedImageFile!.path),
                    fit: BoxFit.contain,
                  ),
                )
              : const Text('No image captured.'),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _captureImage,
            child: const Text('Capture Image'),
          ),
          ElevatedButton(
            onPressed: _verifyImage,
            child: const Text('Verify Image'),
          ),
        ],
      ),
    );
  }
}
