import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_service.dart';
import '../../domain/entities/food.dart';

class FoodRemoteDataSource {
  final ApiService _api;
  FoodRemoteDataSource(this._api);

  String get _apiKey => dotenv.env['GROK_API_KEY'] ?? '';

  Future<Either<Failure, Food>> detectFoodAndCalories(File imageFile) async {
    try {
      if (!imageFile.existsSync()) {
        return left(CacheFailure('File not found', cause: imageFile.path));
      }
      if (_apiKey.isEmpty) {
        return left(const NetworkFailure('Missing GROK_API_KEY'));
      }

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final response = await _api.postJson(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: {
          'model': 'qwen/qwen3.8-27b',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
                {
                  'type': 'text',
                  'text':
                      'Analyze this image and identify the food. '
                      'Estimate its calories, protein, carbs, and fat. '
                      'Return JSON only, no markdown, no explanation, in this exact format: '
                      '{"name": "food name", "calories": 100, "protein": 10, "carbs": 20, "fat": 5}',
                },
              ],
            },
          ],
          'max_tokens': 1000,
        },
      );

      return response.flatMap((data) {
        try {
          final output = data['choices']?[0]?['message']?['content'];
          if (output is! String) {
            return left(NetworkFailure('Invalid API response', cause: data));
          }

          final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(output);
          if (match == null) {
            return left(NetworkFailure('No JSON found in response', cause: output));
          }

          final foodData = jsonDecode(match.group(0)!);
          if (foodData is! Map) {
            return left(NetworkFailure('Invalid JSON in response', cause: output));
          }

          return right(
            Food(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: foodData['name'] as String,
              calories: (foodData['calories'] as num).toDouble(),
              protein: (foodData['protein'] as num).toDouble(),
              carbs: (foodData['carbs'] as num).toDouble(),
              fat: (foodData['fat'] as num).toDouble(),
              quantity: 100.0,
              timestamp: DateTime.now(),
            ),
          );
        } catch (e) {
          return left(NetworkFailure('Failed to parse API response', cause: e));
        }
      });
    } catch (e) {
      return left(NetworkFailure('Failed to detect food', cause: e));
    }
  }
}

