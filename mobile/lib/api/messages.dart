import 'api_client.dart';

/// Maps machine-readable API error codes to Turkish UI messages (see DECISIONS D-011).
String errorMessage(Object error) {
  if (error is! ApiException) return 'Beklenmeyen bir hata oluştu.';
  switch (error.code) {
    case 'network':
      return 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edin.';
    case 'invalid_credentials':
      return 'E-posta veya şifre hatalı.';
    case 'email_not_verified':
      return 'Lütfen önce e-posta adresinizi doğrulayın.';
    case 'email_taken':
      return 'Bu e-posta adresiyle zaten bir hesap var.';
    case 'invalid_token':
      return 'Kod geçersiz veya süresi dolmuş.';
    case 'rate_limited':
      return 'Çok fazla deneme yaptınız. Lütfen biraz bekleyin.';
    case 'validation_error':
      return 'Girilen bilgileri kontrol edin.';
    case 'already_in_playlist':
      return 'Bu parça zaten çalma listesinde.';
    case 'limit_reached':
      return 'Limit doldu.';
    case 'not_found':
      return 'Bulunamadı.';
    case 'unauthorized':
      return 'Oturumunuzun süresi doldu. Lütfen tekrar giriş yapın.';
    default:
      return 'Bir hata oluştu (${error.statusCode}).';
  }
}

/// Client-side mirror of the server password policy, for instant feedback.
String? validatePassword(String? value) {
  final v = value ?? '';
  if (v.length < 10) return 'Şifre en az 10 karakter olmalı.';
  if (v.length > 128) return 'Şifre en fazla 128 karakter olabilir.';
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return 'Şifre en az bir harf ve bir rakam içermeli.';
  }
  return null;
}

String? validateEmail(String? value) {
  final v = (value ?? '').trim();
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return 'Geçerli bir e-posta adresi girin.';
  return null;
}
