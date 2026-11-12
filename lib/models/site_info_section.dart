/// The four public information documents are states of one page.
enum SiteInfoSection {
  about,
  guidelines,
  terms,
  privacy;

  /// Accept canonical Discourse URLs and their trailing-slash variants.
  /// Callers must check the origin before treating an absolute URL as local.
  static SiteInfoSection? fromPath(String path) {
    final normalized = path.trim().toLowerCase().replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return switch (normalized) {
      '/about' => SiteInfoSection.about,
      '/guidelines' => SiteInfoSection.guidelines,
      '/tos' => SiteInfoSection.terms,
      '/privacy' => SiteInfoSection.privacy,
      _ => null,
    };
  }
}
