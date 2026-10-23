import 'package:flutter/material.dart';

/// A care category shown on the TV home screen.
@immutable
class CareOption {
  const CareOption({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    required this.promptTemplate,
    required this.symptoms,
    required this.accentColor,
  });

  /// Stable identifier (also sent to the backend as `category`).
  final String id;

  /// Human readable category title.
  final String title;

  /// One or two sentences describing what the category covers.
  final String description;

  /// Name of the Material icon used for this category (see [icon]).
  final String iconName;

  /// Prompt sent to the model. `{symptom}` is replaced by [buildPrompt].
  final String promptTemplate;

  /// Common concerns the viewer can pick with the remote.
  final List<String> symptoms;

  /// ARGB colour value used for focus glow and highlights.
  final int accentColor;

  Color get accent => Color(accentColor);

  IconData get icon {
    switch (iconName) {
      case 'health_and_safety':
        return Icons.health_and_safety_rounded;
      case 'elderly':
        return Icons.elderly_rounded;
      case 'agriculture':
        return Icons.agriculture_rounded;
      case 'emergency':
        return Icons.emergency_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }

  /// Builds the final prompt for a selected concern.
  String buildPrompt(String symptom) =>
      promptTemplate.replaceAll('{symptom}', symptom);

  /// The four categories offered by CareTV AI.
  static const List<CareOption> all = <CareOption>[
    CareOption(
      id: 'household',
      title: 'Household Health',
      description:
          'Everyday illness and minor injuries for the whole family, with safe home-care steps.',
      iconName: 'health_and_safety',
      accentColor: 0xFF2DD4BF,
      promptTemplate:
          'A family member at home has this concern: "{symptom}". Give safe home-care guidance '
          'for a non-medical caregiver without special equipment, and explain clearly which '
          'warning signs mean a doctor must be contacted.',
      symptoms: <String>[
        'Fever and chills',
        'Persistent cough',
        'Stomach pain and nausea',
        'Minor cuts and burns',
      ],
    ),
    CareOption(
      id: 'elderly',
      title: 'Elderly Care',
      description:
          'Gentle guidance for older adults: falls, medication, nutrition and memory concerns.',
      iconName: 'elderly',
      accentColor: 0xFFA78BFA,
      promptTemplate:
          'A caregiver is looking after an older adult who has this concern: "{symptom}". '
          'Give calm, practical caregiving guidance, mention medication and fall-safety points '
          'where relevant, and list the signs that need urgent medical attention.',
      symptoms: <String>[
        'Dizziness and falls',
        'Missed medication',
        'Poor appetite and weight loss',
        'Confusion or memory lapses',
      ],
    ),
    CareOption(
      id: 'livestock',
      title: 'Livestock & Farm Care',
      description:
          'First response for cattle, goats, sheep and poultry until a veterinarian can attend.',
      iconName: 'agriculture',
      accentColor: 0xFF84CC16,
      promptTemplate:
          'A small farmer has this animal health concern: "{symptom}" (cattle, goats, sheep or '
          'poultry). Give practical first-response guidance that can be done on a farm, include '
          'biosecurity and isolation advice, and say when a veterinarian or the livestock '
          'authorities must be called.',
      symptoms: <String>[
        'Not eating or drinking',
        'Limping or leg injury',
        'Bloated belly',
        'Poultry respiratory signs',
      ],
    ),
    CareOption(
      id: 'emergency',
      title: 'Emergency First Aid',
      description:
          'Step-by-step first aid for life-threatening situations while help is on the way.',
      iconName: 'emergency',
      accentColor: 0xFFF87171,
      promptTemplate:
          'There is an emergency: "{symptom}". Give clear, numbered first-aid steps that a '
          'bystander can follow immediately, starting with calling the local emergency number, '
          'and state what NOT to do.',
      symptoms: <String>[
        'Choking',
        'Severe bleeding',
        'Fainting or unresponsive',
        'Chest pain',
      ],
    ),
  ];
}
