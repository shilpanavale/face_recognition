import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isProcessing = false;
  bool _isFrontCamera = false;


  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    _initializeController(_cameras![0]);
  }

  Future<void> _initializeController(CameraDescription cameraDescription) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(cameraDescription, ResolutionPreset.high);

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  void _toggleCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;

    // Switch between front and back cameras
    final newCameraIndex = _isFrontCamera ? 1 : 0; // Assuming [0] is the back and [1] is the front camera
    await _initializeController(_cameras![newCameraIndex]);
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Camera'),
        actions: [
          IconButton(
            icon: Icon(Icons.switch_camera),
            onPressed: _toggleCamera,
          ),
        ],
      ),
      body: CameraPreview(_cameraController!),
      floatingActionButton:
       FloatingActionButton(
        onPressed: () async {
          if (_cameraController == null || !_cameraController!.value.isInitialized) return;
          try {
            // Capture the image
            final image = await _cameraController!.takePicture();

            // Return to the previous page with the captured image
            if (context.mounted) {
              Navigator.pop(context, image);
            }
           
          } catch (e) {
            print('Error capturing image: $e');
          } finally {
            _isProcessing = false;
          }
        },
        child: Text('Capture'),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
