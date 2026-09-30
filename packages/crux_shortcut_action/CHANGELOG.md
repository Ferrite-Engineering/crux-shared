# Changelog

## 0.0.1

- Initial extraction. `ActionCategory` enum lifted verbatim from WaveCrux
  open-core (`lib/core/shortcuts/action_category.dart`); `CruxAction`
  abstract interface introduced so each product's action enum can implement
  it while keeping product-specific values, labels, and Intent subclasses
  in each product.
