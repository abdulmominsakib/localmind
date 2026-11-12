# Historical state-pack controls

These complete model-free journals were emitted by the original catalog runners,
not reconstructed by the catalog-11 runner. Both contain 15 passing core cases.
They are importer regression fixtures, not model/runtime qualification.

- Catalog 9: source `1526ac69f98b585066b7183a9d385c21ef2374d1`.
- Catalog 10: source `7b44e3e32881e3d054747368d696b6f1b8b42de4`.

The original `test/validation_test.dart` CountingFakeEngine runs the locked
`tiny-gguf-cpu` profile. Its detokenizer prepends the profile's declared single
space, so C02 tests the original oracle. The runner writes its native catalog,
case versions, fixture hashes and event order. Replaying these exact bytes
must retain all results. Placeholder source provenance belongs to the original
model-free test double and makes no claim about a real deployed runtime.
