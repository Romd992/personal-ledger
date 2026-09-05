import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 图片压缩服务
class ImageCompressService {
  static const int _maxWidth = 1280;
  static const int _maxHeight = 1280;
  static const int _quality = 75;

  /// 压缩单张图片，返回压缩后的文件路径
  static Future<String> compressImage(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return sourcePath;
      }

      // 读取图片
      final bytes = await sourceFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return sourcePath;
      }

      // 计算缩放比例
      double scale = 1.0;
      if (image.width > _maxWidth) {
        scale = _maxWidth / image.width;
      }
      if (image.height > _maxHeight) {
        final hScale = _maxHeight / image.height;
        if (hScale < scale) scale = hScale;
      }

      // 缩放图片
      img.Image compressedImage;
      if (scale < 1.0) {
        final newWidth = (image.width * scale).round();
        final newHeight = (image.height * scale).round();
        compressedImage = img.copyResize(image, width: newWidth, height: newHeight);
      } else {
        compressedImage = image;
      }

      // 编码为JPEG
      final compressedBytes = img.encodeJpg(compressedImage, quality: _quality);

      // 保存到应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/voucher_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final uuid = const Uuid().v4();
      final outputPath = '${imagesDir.path}/voucher_$uuid.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(compressedBytes);

      return outputPath;
    } catch (e) {
      return sourcePath;
    }
  }

  /// 批量压缩图片，返回压缩后的文件路径列表
  static Future<List<String>> compressImages(List<String> sourcePaths) async {
    final results = <String>[];
    for (final path in sourcePaths) {
      final compressed = await compressImage(path);
      results.add(compressed);
    }
    return results;
  }

  /// 获取凭证图片目录
  static Future<String> getVoucherImagesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/voucher_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir.path;
  }

  /// 删除凭证图片
  static Future<void> deleteVoucherImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 计算图片大小（KB）
  static Future<double> getImageSizeKB(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        return bytes / 1024;
      }
    } catch (_) {}
    return 0;
  }
}
