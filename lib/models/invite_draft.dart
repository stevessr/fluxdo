/// The two Discourse invitation flows share a form but submit different fields.
enum InviteDeliveryMethod { link, email }

enum InviteDraftValidation { invalidEmail, invalidDomain, invalidRedemptions }

class InviteDraft {
  const InviteDraft({
    required this.method,
    required this.advanced,
    this.emailInput = '',
    this.domainInput = '',
    this.maxRedemptionsInput = '1',
    this.descriptionInput = '',
    this.customMessageInput = '',
  });

  final InviteDeliveryMethod method;
  final bool advanced;
  final String emailInput;
  final String domainInput;
  final String maxRedemptionsInput;
  final String descriptionInput;
  final String customMessageInput;

  InviteDraftValidation? get validation {
    if (method == InviteDeliveryMethod.email) {
      final email = emailInput.trim();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        return InviteDraftValidation.invalidEmail;
      }
    } else if (advanced) {
      final domain = domainInput.trim();
      if (domain.isNotEmpty &&
          (!RegExp(r'^(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$').hasMatch(domain) ||
              domain.contains('..') ||
              domain.split('.').any(
                (label) => label.startsWith('-') || label.endsWith('-'),
              ))) {
        return InviteDraftValidation.invalidDomain;
      }
      final max = int.tryParse(maxRedemptionsInput.trim());
      if (max == null || max < 1) {
        return InviteDraftValidation.invalidRedemptions;
      }
    }
    return null;
  }

  String? get email =>
      method == InviteDeliveryMethod.email ? emailInput.trim() : null;

  String? get domain => method == InviteDeliveryMethod.link && advanced
      ? _nonEmpty(domainInput)
      : null;

  int get maxRedemptionsAllowed =>
      method == InviteDeliveryMethod.link && advanced
          ? (int.tryParse(maxRedemptionsInput.trim()) ?? 1)
          : 1;

  String? get description =>
      advanced ? _nonEmpty(descriptionInput) : null;

  String? get customMessage =>
      advanced && method == InviteDeliveryMethod.email
          ? _nonEmpty(customMessageInput)
          : null;

  static String? _nonEmpty(String input) {
    final trimmed = input.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
