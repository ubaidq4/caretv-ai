import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/care_option.dart';

/// Where an [AdviceResult] came from.
enum AdviceSource { bedrockProxy, bedrockDirect, offlineDemo }

/// The answer shown on the detail screen.
@immutable
class AdviceResult {
  const AdviceResult({
    required this.text,
    required this.source,
    required this.modelLabel,
    this.note,
  });

  /// Plain-text advice using the headings described in [AdviceFormat].
  final String text;
  final AdviceSource source;

  /// Short label such as "Claude 3 Haiku" shown in the status chip.
  final String modelLabel;

  /// Optional human readable note (for example why the offline demo was used).
  final String? note;

  bool get isLive => source != AdviceSource.offlineDemo;
}

/// Helpers for the simple text format used for advice.
///
/// Headings are upper-case lines that end with a colon, for example
/// `ASSESSMENT:` or `WHAT TO DO NOW:`.
class AdviceFormat {
  AdviceFormat._();

  static final RegExp _heading = RegExp(r"^[A-Z][A-Z /&'-]{3,}:$");

  static bool isHeading(String line) => _heading.hasMatch(line.trim());
}

/// Build-time configuration, supplied with `--dart-define`.
///
/// Example:
/// ```
/// flutter run \
///   --dart-define=CARETV_API_URL=https://abc123.execute-api.us-east-1.amazonaws.com/prod/advice \
///   --dart-define=CARETV_API_KEY=my-api-gateway-key
/// ```
class BedrockConfig {
  BedrockConfig._();

  /// API Gateway / Lambda proxy URL (recommended for production).
  static const String proxyUrl = String.fromEnvironment('CARETV_API_URL');

  /// Optional API Gateway API key, sent as `x-api-key`.
  static const String proxyApiKey = String.fromEnvironment('CARETV_API_KEY');

  /// Amazon Bedrock API key for direct calls (demo use only - see README).
  static const String bedrockApiKey =
      String.fromEnvironment('CARETV_BEDROCK_API_KEY');

  static const String region =
      String.fromEnvironment('CARETV_AWS_REGION', defaultValue: 'us-east-1');

  static const String modelId = String.fromEnvironment(
    'CARETV_MODEL_ID',
    defaultValue: 'anthropic.claude-3-haiku-20240307-v1:0',
  );
}

/// Talks to AWS Bedrock and falls back to built-in demo answers when offline.
///
/// Modes, chosen automatically:
/// 1. **Proxy** - `CARETV_API_URL` is set. The app calls your API Gateway +
///    Lambda, which invokes Bedrock with its own IAM role. No AWS secret ships
///    inside the APK.
/// 2. **Direct** - `CARETV_BEDROCK_API_KEY` is set. The app calls the Bedrock
///    runtime `InvokeModel` endpoint with a Bedrock API key (bearer token).
/// 3. **Offline demo** - nothing is configured, or the request failed.
class AWSBedrockService {
  AWSBedrockService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 25);
  static const int _maxTokens = 700;

  static const String _systemPrompt =
      'You are CareTV AI, a calm and caring assistant that gives general caretaking '
      'guidance to families, caregivers of older adults, small farmers and bystanders in '
      'emergencies. You provide general information only and never claim to diagnose. '
      'Write plain English that is easy to listen to on a TV speaker. Do not use markdown '
      'symbols. Use exactly these headings, each on its own line: ASSESSMENT: then '
      'WHAT TO DO NOW: (short numbered steps) then WARNING SIGNS: (lines starting with "- ") '
      'then WHEN TO GET HELP:. Keep the whole answer under 220 words.';

  bool get isConfigured =>
      BedrockConfig.proxyUrl.isNotEmpty || BedrockConfig.bedrockApiKey.isNotEmpty;

  bool get _isTitan => BedrockConfig.modelId.startsWith('amazon.titan');

  String get _modelLabel {
    final String id = BedrockConfig.modelId;
    if (id.contains('claude-3-haiku')) return 'Claude 3 Haiku';
    if (id.startsWith('amazon.titan')) return 'Amazon Titan';
    return id;
  }

  /// Returns advice for [symptom] inside [option]. Never throws.
  Future<AdviceResult> getAdvice({
    required CareOption option,
    required String symptom,
  }) async {
    if (!isConfigured) {
      return _fallback(
        option,
        symptom,
        'No AWS endpoint configured - showing built-in demo guidance.',
      );
    }

    try {
      final String prompt = option.buildPrompt(symptom);
      final Map<String, dynamic> nativeBody = _buildNativeBody(prompt);
      final bool useProxy = BedrockConfig.proxyUrl.isNotEmpty;

      final String raw = useProxy
          ? await _invokeProxy(option, symptom, prompt, nativeBody)
          : await _invokeDirect(nativeBody);

      final String text = _normalize(raw);
      if (text.isEmpty) {
        throw const FormatException('Empty model response');
      }
      return AdviceResult(
        text: text,
        source:
            useProxy ? AdviceSource.bedrockProxy : AdviceSource.bedrockDirect,
        modelLabel: _modelLabel,
      );
    } on TimeoutException {
      return _fallback(option, symptom,
          'AWS request timed out - showing built-in demo guidance.');
    } catch (e, st) {
      debugPrint('AWSBedrockService error: $e\n$st');
      return _fallback(option, symptom,
          'Could not reach AWS Bedrock - showing built-in demo guidance.');
    }
  }

  // ---------------------------------------------------------------------------
  // Request building
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildNativeBody(String prompt) {
    if (_isTitan) {
      return <String, dynamic>{
        'inputText': '$_systemPrompt\n\n$prompt',
        'textGenerationConfig': <String, dynamic>{
          'maxTokenCount': _maxTokens,
          'temperature': 0.4,
          'topP': 0.9,
        },
      };
    }
    return <String, dynamic>{
      'anthropic_version': 'bedrock-2023-05-31',
      'max_tokens': _maxTokens,
      'temperature': 0.4,
      'system': _systemPrompt,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, String>>[
            <String, String>{'type': 'text', 'text': prompt},
          ],
        },
      ],
    };
  }

  Future<String> _invokeProxy(
    CareOption option,
    String symptom,
    String prompt,
    Map<String, dynamic> nativeBody,
  ) async {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (BedrockConfig.proxyApiKey.isNotEmpty)
        'x-api-key': BedrockConfig.proxyApiKey,
    };

    final http.Response response = await _client
        .post(
          Uri.parse(BedrockConfig.proxyUrl),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'category': option.id,
            'concern': symptom,
            'prompt': prompt,
            'systemPrompt': _systemPrompt,
            'modelId': BedrockConfig.modelId,
            // Native Bedrock payload: a Lambda can forward this untouched.
            'body': nativeBody,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw http.ClientException(
          'Proxy returned HTTP ${response.statusCode}', Uri.parse(BedrockConfig.proxyUrl));
    }
    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return _extractText(decoded) ?? '';
  }

  Future<String> _invokeDirect(Map<String, dynamic> nativeBody) async {
    final Uri uri = Uri.https(
      'bedrock-runtime.${BedrockConfig.region}.amazonaws.com',
      '/model/${BedrockConfig.modelId}/invoke',
    );

    final http.Response response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer ${BedrockConfig.bedrockApiKey}',
          },
          body: jsonEncode(nativeBody),
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw http.ClientException(
          'Bedrock returned HTTP ${response.statusCode}', uri);
    }
    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return _extractText(decoded) ?? '';
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  /// Understands the plain proxy shape (`{"text": "..."}`), Claude
  /// (`content[].text`), Titan (`results[0].outputText`), Nova / Converse
  /// (`output.message.content[].text`) and API Gateway envelopes (`body`).
  String? _extractText(dynamic data) {
    if (data is String) {
      final String t = data.trim();
      if (t.startsWith('{') || t.startsWith('[')) {
        try {
          return _extractText(jsonDecode(t));
        } catch (_) {
          // Not JSON after all - treat it as plain text.
        }
      }
      return t.isEmpty ? null : t;
    }

    if (data is Map) {
      for (final String key in const <String>[
        'text',
        'advice',
        'response',
        'completion',
        'outputText',
        'output',
      ]) {
        final dynamic value = data[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }

      final dynamic content = data['content'];
      if (content is List) {
        final StringBuffer buffer = StringBuffer();
        for (final dynamic part in content) {
          if (part is Map && part['text'] is String) {
            buffer.write(part['text']);
          }
        }
        if (buffer.isNotEmpty) return buffer.toString().trim();
      }

      final dynamic results = data['results'];
      if (results is List && results.isNotEmpty) {
        return _extractText(results.first);
      }

      final dynamic output = data['output'];
      if (output is Map) {
        return _extractText(output['message'] ?? output);
      }

      final dynamic body = data['body'];
      if (body != null) return _extractText(body);
    }
    return null;
  }

  /// Strips markdown that would look odd on screen or sound odd when spoken.
  String _normalize(String raw) {
    String t = raw.replaceAll('\r\n', '\n');
    t = t.replaceAll(RegExp(r'\*\*|__|`'), '');
    t = t.replaceAllMapped(
      RegExp(r'^[ \t]*#{1,6}[ \t]*(.+?)[ \t]*:?[ \t]*$', multiLine: true),
      (Match m) => '${m[1]!.toUpperCase()}:',
    );
    t = t.replaceAllMapped(
      RegExp(r'^[ \t]*[*\u2022][ \t]+', multiLine: true),
      (Match m) => '- ',
    );
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  // ---------------------------------------------------------------------------
  // Offline demo answers
  // ---------------------------------------------------------------------------

  Future<AdviceResult> _fallback(
    CareOption option,
    String symptom,
    String note,
  ) async {
    // Small delay so the "analyzing" state is visible and feels natural.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final _Fallback entry = _fallbacks[symptom] ?? _genericFallback(symptom);
    return AdviceResult(
      text: _format(entry),
      source: AdviceSource.offlineDemo,
      modelLabel: 'Built-in demo',
      note: note,
    );
  }

  String _format(_Fallback f) {
    final StringBuffer b = StringBuffer()
      ..writeln('ASSESSMENT:')
      ..writeln(f.assessment)
      ..writeln()
      ..writeln('WHAT TO DO NOW:');
    for (int i = 0; i < f.steps.length; i++) {
      b.writeln('${i + 1}. ${f.steps[i]}');
    }
    b
      ..writeln()
      ..writeln('WARNING SIGNS:');
    for (final String w in f.warnings) {
      b.writeln('- $w');
    }
    b
      ..writeln()
      ..writeln('WHEN TO GET HELP:')
      ..write(f.help);
    return b.toString();
  }

  _Fallback _genericFallback(String symptom) => _Fallback(
        assessment:
            'General guidance for "$symptom". This offline demo cannot assess the situation in detail.',
        steps: const <String>[
          'Stay calm and keep the person or animal in a safe, comfortable place.',
          'Note when it started, how it has changed, and any medicines already given.',
          'Offer clean water unless there is vomiting, choking or unconsciousness.',
          'Contact a doctor or veterinarian and describe what you noted.',
        ],
        warnings: const <String>[
          'Trouble breathing or severe pain',
          'Confusion, fainting or unresponsiveness',
          'Symptoms that are getting worse quickly',
        ],
        help:
            'Call a doctor, veterinarian or your local emergency number if any warning sign appears.',
      );

  static const Map<String, _Fallback> _fallbacks = <String, _Fallback>{
    // ---- Household Health --------------------------------------------------
    'Fever and chills': _Fallback(
      assessment:
          'Fever is often the body fighting an infection such as flu or a viral illness. A temperature above 38 degrees Celsius (100.4 F) counts as a fever.',
      steps: <String>[
        'Rest and drink fluids often: water, oral rehydration solution or clear soup.',
        'Check the temperature every four hours and write it down.',
        'Dress in light clothing and use a lukewarm, not cold, sponge if uncomfortable.',
        'Paracetamol can be used exactly as the label says. Never give aspirin to children.',
      ],
      warnings: <String>[
        'Temperature above 39.5 C (103 F) or lasting more than 3 days',
        'Stiff neck, new rash, confusion or trouble breathing',
        'Any fever in a baby younger than 3 months',
      ],
      help:
          'Contact a doctor the same day if any warning sign appears. Go to emergency care for breathing trouble or confusion.',
    ),
    'Persistent cough': _Fallback(
      assessment:
          'A cough lasting more than two to three weeks can come from a lingering infection, allergies, asthma or acid reflux.',
      steps: <String>[
        'Drink warm fluids. Honey in warm water can soothe the throat for anyone older than one year.',
        'Keep the air clean: avoid smoke, dust and strong smells.',
        'Raise the head with an extra pillow when sleeping.',
        'Keep a note of when the cough is worst, such as night or after meals.',
      ],
      warnings: <String>[
        'Coughing up blood',
        'Shortness of breath, wheezing or chest pain',
        'Fever with night sweats or unexplained weight loss',
      ],
      help:
          'See a doctor if the cough lasts more than three weeks. Seek urgent care for breathing difficulty.',
    ),
    'Stomach pain and nausea': _Fallback(
      assessment:
          'Stomach pain with nausea is often caused by a food upset, a stomach infection or acidity, and usually settles within a day or two.',
      steps: <String>[
        'Take small, frequent sips of oral rehydration solution or water.',
        'Avoid oily, spicy and heavy food. Try plain rice, toast or banana once nausea eases.',
        'Rest, and wash hands well to avoid spreading infection.',
        'Do not give strong painkillers without medical advice.',
      ],
      warnings: <String>[
        'Severe or constant pain, especially in the lower right belly',
        'Blood in vomit or stool, or black stools',
        'No urination for 8 hours or vomiting for more than 24 hours',
      ],
      help:
          'See a doctor within 24 hours if it does not improve. Go to emergency care for severe pain.',
    ),
    'Minor cuts and burns': _Fallback(
      assessment:
          'Small cuts and minor burns usually heal well at home when kept clean.',
      steps: <String>[
        'Wash your hands. For a cut, press a clean cloth on it for about 10 minutes, then rinse with clean running water.',
        'For a burn, cool it under cool running water for 20 minutes. Do not use ice, butter or toothpaste.',
        'Cover with a clean, non-stick dressing and change it daily.',
        'Check that tetanus vaccination is up to date for dirty wounds.',
      ],
      warnings: <String>[
        'Deep or gaping wound, or bleeding that does not stop after 10 minutes',
        'Burn larger than the person\'s palm, or on the face, hands or joints',
        'Spreading redness, pus or fever',
      ],
      help:
          'Visit a clinic for any of the warning signs. Call emergency services for large or deep burns.',
    ),

    // ---- Elderly Care ------------------------------------------------------
    'Dizziness and falls': _Fallback(
      assessment:
          'Dizziness in older adults is often linked to low blood pressure, dehydration, medicine side effects or inner-ear problems, and it raises the risk of falls.',
      steps: <String>[
        'Help the person sit or lie down right away and offer water.',
        'If they have fallen, do not move them when there is neck, back or hip pain. Call for help.',
        'Stand up slowly in future: sit on the bed edge for a minute first.',
        'Remove trip hazards, add good lighting and use non-slip footwear.',
      ],
      warnings: <String>[
        'A fall with a hit to the head',
        'Sudden weakness on one side, slurred speech or facial droop',
        'Chest pain, fainting or a severe headache',
      ],
      help:
          'Call emergency services for stroke signs or a head injury. Ask the doctor to review medicines if dizziness repeats.',
    ),
    'Missed medication': _Fallback(
      assessment:
          'An occasional missed dose is common. The right action depends on the medicine, so check before doing anything.',
      steps: <String>[
        'Read the label or leaflet for missed-dose advice.',
        'Do not double the next dose unless the doctor or pharmacist says so.',
        'Write down which medicine was missed and when.',
        'Set up a pill organizer and a daily reminder to prevent it happening again.',
      ],
      warnings: <String>[
        'Missed insulin, blood thinners, heart, blood pressure or epilepsy medicine',
        'Symptoms coming back after a missed dose',
        'Doses being missed repeatedly',
      ],
      help:
          'Call the pharmacist or doctor the same day for high-risk medicines or repeated missed doses.',
    ),
    'Poor appetite and weight loss': _Fallback(
      assessment:
          'Appetite often falls with age, but weight loss without trying needs a medical check. Causes include dental problems, low mood, medicines or illness.',
      steps: <String>[
        'Offer five or six small meals a day instead of three large ones.',
        'Add protein such as eggs, lentils, yogurt or milk, and favorite foods.',
        'Keep fluids available and eat together when possible.',
        'Check the mouth and dentures for pain or poor fit.',
      ],
      warnings: <String>[
        'Difficulty swallowing or repeated vomiting',
        'Blood in stool',
        'Noticeable weight loss over a few weeks or signs of dehydration',
      ],
      help:
          'Book a doctor visit within a week, sooner if any warning sign is present.',
    ),
    'Confusion or memory lapses': _Fallback(
      assessment:
          'Sudden confusion can signal infection, dehydration, a medicine reaction or a stroke. Slowly growing memory lapses may need a dementia check.',
      steps: <String>[
        'Stay calm, speak slowly and keep the room quiet and well lit.',
        'Offer water and check for pain or a full bladder. If diabetic, check blood sugar.',
        'Make the area safe and stay with the person.',
        'Write down when the confusion began and any recent changes in medicine.',
      ],
      warnings: <String>[
        'Sudden onset, facial droop, weakness or trouble speaking',
        'Fever or a severe headache',
        'Not recognizing close family or being unable to stay awake',
      ],
      help:
          'Call emergency services right away for sudden confusion. Arrange a routine doctor visit for gradual memory changes.',
    ),

    // ---- Livestock & Farm Care --------------------------------------------
    'Not eating or drinking': _Fallback(
      assessment:
          'Loss of appetite in cattle, goats or sheep is an early sign of illness such as fever, rumen upset, infection, parasites or pain.',
      steps: <String>[
        'Separate the animal into a clean, shaded pen away from the herd.',
        'Offer fresh clean water and good quality fodder.',
        'If you are trained, take the temperature. Normal for cattle is about 38 to 39.5 C.',
        'Watch rumen movement, dung, urine and milk yield, and write down changes.',
      ],
      warnings: <String>[
        'Temperature above 40 C',
        'No chewing of cud for more than 24 hours or a swollen left flank',
        'Mouth or hoof blisters, drooling, blood in dung or urine',
      ],
      help:
          'Call a veterinarian within 24 hours. Report blisters and drooling to the local livestock authority immediately.',
    ),
    'Limping or leg injury': _Fallback(
      assessment:
          'Limping is usually caused by a hoof problem, a wound, a sprain or an infection between the toes.',
      steps: <String>[
        'Rest the animal on soft, dry bedding and do not force it to walk.',
        'Lift and inspect the hoof for stones, cuts, swelling or foul smell.',
        'Clean wounds with clean water and a mild antiseptic. Keep the foot dry.',
        'Separate the animal and watch whether others are also limping.',
      ],
      warnings: <String>[
        'Hot swelling, pus or a bad smell',
        'The animal will not put weight on the leg',
        'Fever, or several animals limping with mouth blisters',
      ],
      help:
          'Call a veterinarian if there is no improvement in two days, or at once for any warning sign.',
    ),
    'Bloated belly': _Fallback(
      assessment:
          'Bloat is gas trapped in the rumen. It can become life-threatening within hours.',
      steps: <String>[
        'Call a veterinarian immediately.',
        'Keep the animal standing and calm. Gentle walking can help.',
        'Stop all grain, wet clover and legume feed.',
        'Do not try to puncture the belly unless a veterinarian instructs you.',
      ],
      warnings: <String>[
        'Tight, swollen left flank',
        'Labored breathing or tongue sticking out',
        'Collapse or lying down and unable to rise',
      ],
      help:
          'This is an emergency. Call a veterinarian now and keep following their phone instructions.',
    ),
    'Poultry respiratory signs': _Fallback(
      assessment:
          'Sneezing, gasping, nasal discharge or a swollen face in poultry can be caused by Newcastle disease, infectious bronchitis, coryza or avian influenza.',
      steps: <String>[
        'Isolate sick birds at once and handle them last, wearing gloves and a mask.',
        'Improve ventilation without drafts and reduce dust.',
        'Provide clean water and clean feeders. Do not move or sell birds or eggs.',
        'Keep a daily record of sick birds, deaths and egg production.',
      ],
      warnings: <String>[
        'Many sudden deaths',
        'Purple, swollen combs or twisted necks',
        'A sharp drop in egg production',
      ],
      help:
          'Contact a veterinarian or the local livestock department immediately, because some of these diseases must be reported.',
    ),

    // ---- Emergency First Aid ----------------------------------------------
    'Choking': _Fallback(
      assessment:
          'Choking is an emergency when the person cannot cough, speak or breathe.',
      steps: <String>[
        'Ask "Are you choking?" If they can cough, encourage them to keep coughing.',
        'Call your local emergency number, or ask someone else to.',
        'Give up to 5 firm back blows between the shoulder blades with the heel of your hand.',
        'Then give up to 5 abdominal thrusts above the navel. Alternate back blows and thrusts.',
        'If the person becomes unresponsive, start CPR. For babies use back blows and two-finger chest thrusts, never abdominal thrusts.',
      ],
      warnings: <String>[
        'Cannot speak, cough or breathe',
        'Blue or gray lips and skin',
        'Person collapses',
      ],
      help:
          'Call emergency services immediately. Anyone who needed abdominal thrusts should be checked by a doctor afterwards.',
    ),
    'Severe bleeding': _Fallback(
      assessment:
          'Heavy bleeding can become life-threatening in minutes, so controlling it quickly is the priority.',
      steps: <String>[
        'Call your local emergency number.',
        'Press firmly and directly on the wound with a clean cloth or gauze.',
        'If blood soaks through, add more cloth on top. Do not remove the first layer.',
        'Raise the injured limb if you do not suspect a fracture, and keep the person lying down and warm.',
        'Do not remove objects stuck in the wound.',
      ],
      warnings: <String>[
        'Pale, cold, clammy skin and a fast pulse',
        'Confusion or drowsiness',
        'Bleeding that soaks through repeatedly',
      ],
      help:
          'Emergency services are needed for any heavy bleeding. Keep pressure on until they arrive.',
    ),
    'Fainting or unresponsive': _Fallback(
      assessment:
          'A person who does not respond may have a serious medical problem. Check breathing first.',
      steps: <String>[
        'Tap the shoulders and shout. If there is no response, call your local emergency number.',
        'Look and listen for normal breathing for up to 10 seconds.',
        'If not breathing normally, start chest compressions: push hard and fast in the center of the chest, about 100 to 120 per minute, and use an AED if one is available.',
        'If breathing normally, roll the person onto their side in the recovery position.',
        'If someone faints and wakes quickly, lay them flat, raise the legs, and give nothing to eat or drink until fully alert.',
      ],
      warnings: <String>[
        'Not breathing or only gasping',
        'Fainting with chest pain, injury or a seizure',
        'Not waking up within a minute',
      ],
      help:
          'Always call emergency services for an unresponsive person. Follow the operator\'s instructions.',
    ),
    'Chest pain': _Fallback(
      assessment:
          'Chest pressure or pain with sweating, nausea, breathlessness, or pain spreading to the arm or jaw may be a heart attack.',
      steps: <String>[
        'Call your local emergency number now.',
        'Stop all activity and sit in a comfortable position. Loosen tight clothing.',
        'If the emergency operator advises it and there is no allergy, the person may chew one adult aspirin.',
        'Unlock the door and stay with the person. Be ready to start CPR if they become unresponsive.',
      ],
      warnings: <String>[
        'Pain lasting more than a few minutes or returning',
        'Cold sweat, nausea or breathlessness',
        'Fainting or irregular pulse',
      ],
      help:
          'Treat chest pain as an emergency every time. Do not drive yourself to hospital.',
    ),
  };

  void dispose() => _client.close();
}

/// Compact structure for one offline demo answer.
@immutable
class _Fallback {
  const _Fallback({
    required this.assessment,
    required this.steps,
    required this.warnings,
    required this.help,
  });

  final String assessment;
  final List<String> steps;
  final List<String> warnings;
  final String help;
}
