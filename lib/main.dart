import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced Image Sharpening',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ImageSharpeningPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ImageSharpeningPage extends StatefulWidget {
  const ImageSharpeningPage({super.key});

  @override
  State<ImageSharpeningPage> createState() => _ImageSharpeningPageState();
}

class _ImageSharpeningPageState extends State<ImageSharpeningPage> {
  XFile? _selectedImage;
  String? _selectedImageUrl;
  String? _uploadedFilename;
  bool _isLoading = false;
  double _strength = 1.0;
  
  // نتائج المقارنة
  Map<String, dynamic> _comparison = {};
  Map<String, String> _savedResults = {};
  bool _comparisonDone = false;
  String _errorMessage = '';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      // إنشاء URL للصورة المختارة لعرضها في Web
      final bytes = await pickedFile.readAsBytes();
      final url = Uri.dataFromBytes(bytes, mimeType: 'image/jpeg').toString();
      
      setState(() {
        _selectedImage = pickedFile;
        _selectedImageUrl = url;
        _comparisonDone = false;
        _comparison = {};
        _savedResults = {};
        _errorMessage = '';
        _uploadedFilename = null;
      });
    }
  }

  Future<void> _uploadAndCompare() async {
    if (_selectedImage == null) {
      setState(() {
        _errorMessage = 'Please select an image first';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // قراءة الصورة كـ bytes
      final bytes = await _selectedImage!.readAsBytes();
      
      // إنشاء multipart request يدوياً
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:5000/upload'),
      );
      
      // إضافة الصورة كـ MultipartFile من bytes (تعمل على Web)
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: _selectedImage!.name,
        ),
      );
      
      var uploadResponse = await request.send();
      var uploadData = await uploadResponse.stream.bytesToString();
      var uploadJson = json.decode(uploadData);
      
      if (uploadResponse.statusCode != 200) {
        throw Exception(uploadJson['error'] ?? 'Upload failed');
      }
      
      String filename = uploadJson['filename'];
      
      // الخطوة 2: مقارنة جميع الطرق
      var compareResponse = await http.post(
        Uri.parse('http://127.0.0.1:5000/compare'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'filename': filename,
          'strength': _strength,
        }),
      );
      
      var compareData = json.decode(compareResponse.body);
      
      if (compareResponse.statusCode == 200) {
        setState(() {
          _uploadedFilename = filename;
          _comparison = compareData['comparison'];
          _savedResults = Map<String, String>.from(compareData['saved_results']);
          _comparisonDone = true;
        });
      } else {
        setState(() {
          _errorMessage = compareData['error'] ?? 'Comparison failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e\nMake sure backend is running on port 5000';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getMethodDisplayName(String method) {
    switch (method) {
      case 'spatial_laplacian':
        return 'Spatial (Laplacian)';
      case 'spatial_unsharp':
        return 'Spatial (Unsharp Mask)';
      case 'frequency':
        return 'Frequency (FFT)';
      default:
        return method;
    }
  }

  Widget _buildMetricRow(String label, String value, bool higherIsBetter) {
    Color valueColor = Colors.black;
    if (value != 'N/A') {
      double? numValue = double.tryParse(value.toString().replaceAll('%', ''));
      if (numValue != null) {
        if (higherIsBetter) {
          valueColor = numValue > 0.5 ? Colors.green : Colors.orange;
        } else {
          valueColor = numValue < 100 ? Colors.green : Colors.orange;
        }
      }
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodComparison(String methodName, Map<String, dynamic> metrics) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getMethodDisplayName(methodName),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // الصورة المصغرة
            if (_savedResults.containsKey(methodName))
              Container(
                height: 120,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'http://127.0.0.1:5000/results/${_savedResults[methodName]}',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.broken_image, size: 40),
                      );
                    },
                  ),
                ),
              ),
            
            // المقاييس
            _buildMetricRow('MSE ↓', metrics['MSE']?.toString() ?? 'N/A', false),
            _buildMetricRow('PSNR ↑', metrics['PSNR']?.toString() ?? 'N/A', true),
            _buildMetricRow('SSIM ↑', metrics['SSIM']?.toString() ?? 'N/A', true),
            _buildMetricRow('MAE ↓', metrics['MAE']?.toString() ?? 'N/A', false),
            _buildMetricRow('Correlation ↑', metrics['Correlation']?.toString() ?? 'N/A', true),
            _buildMetricRow('Sharpness Improvement', 
                '${metrics['Sharpness_Improvement_%']?.toString() ?? 'N/A'}%', true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Image Sharpening'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // زر اختيار الصورة
            Center(
              child: ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Select Image from Gallery'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // عرض الصورة المختارة
            if (_selectedImageUrl != null) ...[
              const Text(
                'Original Image:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _selectedImageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // قوة التحسين
            const Text(
              'Sharpening Strength:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _strength,
                    min: 0.1,
                    max: 2.5,
                    divisions: 24,
                    label: _strength.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _strength = value;
                      });
                    },
                  ),
                ),
                Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _strength.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // زر المقارنة
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _uploadAndCompare,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.green,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Compare Methods (Spatial vs Frequency)',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            
            // عرض نتائج المقارنة
            if (_comparisonDone) ...[
              const Divider(thickness: 2),
              const SizedBox(height: 10),
              const Text(
                '📊 QUANTITATIVE ANALYSIS RESULTS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Spatial Domain vs Frequency Domain',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // عرض كل طريقة
              ...(_comparison.keys.map((method) {
                return _buildMethodComparison(method, _comparison[method]);
              }).toList()),
              
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📈 Interpretation Guide:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• ↑ : Higher is better (PSNR, SSIM, Correlation, Sharpness)'),
                    Text('• ↓ : Lower is better (MSE, MAE)'),
                    Text('• SSIM closer to 1 = Better structural similarity'),
                    Text('• Higher Sharpness Improvement = More detail enhancement'),
                  ],
                ),
              ),
            ],
            
            // عرض الأخطاء
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}