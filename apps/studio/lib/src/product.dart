/// The product name shown to users, set once at build time (runbook S13).
///
/// Build with `--dart-define=PRODUCT_NAME=<name>`; `tool/package.dart` passes
/// the same value to the Windows and Linux runners and the installer. The
/// default keeps today's name until the release-day name freeze.
const productName = String.fromEnvironment(
  'PRODUCT_NAME',
  defaultValue: 'XCross Studio',
);
