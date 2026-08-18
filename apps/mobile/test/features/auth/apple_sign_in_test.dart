import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:facteur/core/auth/apple_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateRawNonce', () {
    test('respecte la longueur demandée', () {
      expect(generateRawNonce().length, 32);
      expect(generateRawNonce(length: 64).length, 64);
    });

    test('n\'utilise que des caractères non réservés en URL', () {
      final nonce = generateRawNonce(length: 512);
      expect(RegExp(r'^[A-Za-z0-9\-._]+$').hasMatch(nonce), isTrue);
    });

    test('produit une valeur différente à chaque appel', () {
      final nonces = List<String>.generate(200, (_) => generateRawNonce());
      expect(nonces.toSet().length, 200);
    });

    test('est déterministe pour un Random seedé (harnais de test)', () {
      expect(
        generateRawNonce(random: Random(42)),
        generateRawNonce(random: Random(42)),
      );
    });
  });

  group('sha256OfString', () {
    // C'est le contrat exact qu'Apple puis GoTrue revérifient : Apple reçoit le
    // hash, Supabase reçoit le nonce brut, et compare. Une divergence
    // d'encodage ici casse le login sans message exploitable.
    test('rend le SHA-256 hexadécimal minuscule de l\'UTF-8 de l\'entrée', () {
      const input = 'facteur-nonce';
      expect(sha256OfString(input), sha256.convert(utf8.encode(input)).toString());
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256OfString(input)), isTrue);
    });

    test('vecteur de référence connu', () {
      expect(
        sha256OfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('gère les caractères non ASCII sans lever', () {
      expect(sha256OfString('éàü').length, 64);
    });
  });

  group('formatAppleFullName', () {
    test('assemble prénom et nom', () {
      expect(formatAppleFullName('Ada', 'Lovelace'), 'Ada Lovelace');
    });

    test('tolère un seul champ renseigné', () {
      expect(formatAppleFullName('Ada', null), 'Ada');
      expect(formatAppleFullName(null, 'Lovelace'), 'Lovelace');
    });

    test('rend null quand Apple ne donne rien (connexions suivantes)', () {
      expect(formatAppleFullName(null, null), isNull);
      expect(formatAppleFullName('', '   '), isNull);
    });

    test('nettoie les espaces superflus', () {
      expect(formatAppleFullName('  Ada ', ' Lovelace  '), 'Ada Lovelace');
    });
  });

  group('AppleCredential', () {
    test('expose fullName dérivé des champs Apple', () {
      const credential = AppleCredential(
        idToken: 'jwt',
        rawNonce: 'nonce',
        givenName: 'Ada',
        familyName: 'Lovelace',
      );
      expect(credential.fullName, 'Ada Lovelace');
    });

    test('fullName null quand Apple ne renvoie pas le nom', () {
      const credential = AppleCredential(idToken: 'jwt', rawNonce: 'nonce');
      expect(credential.fullName, isNull);
    });
  });
}
