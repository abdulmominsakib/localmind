# Shadcn UI Form — Reference

## Initial form value

All form fields with matching `id`s are initialized from `ShadForm`'s `initialValue` map. Fields with their own `initialValue` override the form's.

## Get the form value

`formKey.currentState!.value` returns `Map<String, dynamic>`. Use after a successful `saveAndValidate()`.

## setFieldValue

`formKey.currentState!.setFieldValue('username', 'new_username');`

- Pass `notifyField: false` to update only the form value, not the field UI.

## setValue

`formKey.currentState!.setValue({ 'username': '...', 'email': '...' });`

- Pass `notifyFields: false` to update only the form value, not the fields UI.

## Value transformers

- **fromValueTransformer**: Converts form value (e.g. string) to field value (e.g. DateTime).
- **toValueTransformer**: Converts field value back to form value for `value` and validation.

Example: form has `{'date': '2024-02-01'}`; `ShadDatePickerFormField` needs `DateTime`. Use `fromValueTransformer: (value) => DateTime.tryParse(value ?? '')` and `toValueTransformer: (date) => date == null ? null : DateFormat('yyyy-MM-dd').format(date)`.

## Dot notation

- IDs like `user.email` or `profile.settings.theme` create nested maps in `value`.
- `initialValue` must be nested: `{'user': {'name': 'John', 'email': '...'}}`.
- Custom separator: `ShadForm(fieldIdSeparator: '/', ...)` then use `user/name`.
- Disable: `ShadForm(fieldIdSeparator: null, ...)` so `user.email` stays a flat key.

## Form field components

Use inside `ShadForm` with unique `id` and optional `validator`:

- ShadInputFormField
- ShadCheckboxFormField
- ShadSwitchFormField
- ShadSelectFormField
- ShadRadioGroupFormField
- ShadDatePickerFormField / ShadDateRangePickerFormField
- ShadTimePickerFormField
