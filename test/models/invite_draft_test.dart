import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/invite_draft.dart';

void main() {
  group('InviteDraft', () {
    test('simple link ignores stale advanced values', () {
      const draft = InviteDraft(
        method: InviteDeliveryMethod.link,
        advanced: false,
        emailInput: 'other@example.com',
        domainInput: 'example.com',
        maxRedemptionsInput: '200',
        descriptionInput: 'old note',
      );
      expect(draft.validation, isNull);
      expect(draft.email, isNull);
      expect(draft.domain, isNull);
      expect(draft.description, isNull);
      expect(draft.maxRedemptionsAllowed, 1);
    });

    test('advanced link sends domain, count and description without email', () {
      const draft = InviteDraft(
        method: InviteDeliveryMethod.link,
        advanced: true,
        domainInput: ' example.com ',
        maxRedemptionsInput: '5',
        descriptionInput: ' team ',
        emailInput: 'old@example.com',
        customMessageInput: 'should not send',
      );
      expect(draft.validation, isNull);
      expect(draft.domain, 'example.com');
      expect(draft.maxRedemptionsAllowed, 5);
      expect(draft.description, 'team');
      expect(draft.email, isNull);
      expect(draft.customMessage, isNull);
    });

    test('email uses recipient and optional custom message, not domain', () {
      const draft = InviteDraft(
        method: InviteDeliveryMethod.email,
        advanced: true,
        emailInput: ' person+test@example.com ',
        domainInput: 'stale.example.com',
        maxRedemptionsInput: '7',
        customMessageInput: ' Welcome! ',
        descriptionInput: ' colleague ',
      );
      expect(draft.validation, isNull);
      expect(draft.email, 'person+test@example.com');
      expect(draft.domain, isNull);
      expect(draft.maxRedemptionsAllowed, 1);
      expect(draft.customMessage, 'Welcome!');
      expect(draft.description, 'colleague');
    });

    test('simple email does not submit advanced text', () {
      const draft = InviteDraft(
        method: InviteDeliveryMethod.email,
        advanced: false,
        emailInput: 'hello@example.com',
        customMessageInput: 'stale custom message',
        descriptionInput: 'stale description',
      );
      expect(draft.validation, isNull);
      expect(draft.customMessage, isNull);
      expect(draft.description, isNull);
    });

    test('rejects invalid email, domain and redemption count', () {
      expect(
        const InviteDraft(
          method: InviteDeliveryMethod.email,
          advanced: false,
          emailInput: 'invalid',
        ).validation,
        InviteDraftValidation.invalidEmail,
      );
      expect(
        const InviteDraft(
          method: InviteDeliveryMethod.link,
          advanced: true,
          domainInput: 'name@example.com',
        ).validation,
        InviteDraftValidation.invalidDomain,
      );
      expect(
        const InviteDraft(
          method: InviteDeliveryMethod.link,
          advanced: true,
          maxRedemptionsInput: '0',
        ).validation,
        InviteDraftValidation.invalidRedemptions,
      );
    });
  });
}
