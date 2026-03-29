---
name: shadcn_ui-input-otp
description: Build OTP input with ShadInputOTP, ShadInputOTPGroup, ShadInputOTPSlot; maxLength, inputFormatters, ShadInputOTPFormField. Use when adding one-time password or verification code inputs in a Flutter shadcn_ui app.
---

# Shadcn UI — Input OTP

## Instructions

`ShadInputOTP` is an accessible one-time password component with copy-paste support. Use `children` to build the layout: `ShadInputOTPGroup` containing `ShadInputOTPSlot`s, with optional separators (e.g. `Icon(LucideIcons.dot)`). Set `maxLength`; use `onChanged` for the full OTP string. Restrict input with `keyboardType` and `inputFormatters` (e.g. `FilteringTextInputFormatter.digitsOnly`). For forms use `ShadInputOTPFormField` with `id`, `label`, `validator`.

### Basic

```dart
ShadInputOTP(
  onChanged: (v) => print('OTP: $v'),
  maxLength: 6,
  children: const [
    ShadInputOTPGroup(
      children: [
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
      ],
    ),
    Icon(size: 24, LucideIcons.dot),
    ShadInputOTPGroup(
      children: [
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
      ],
    ),
  ],
)
```

### With input formatters (digits only)

```dart
ShadInputOTP(
  onChanged: (v) => print('OTP: $v'),
  maxLength: 4,
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
  ],
  children: const [
    ShadInputOTPGroup(
      children: [
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
      ],
    ),
  ],
)
```

The package also provides `UpperCaseTextInputFormatter` and `LowerCaseTextInputFormatter`.

### Form field

```dart
ShadInputOTPFormField(
  id: 'otp',
  maxLength: 6,
  label: const Text('OTP'),
  description: const Text('Enter your OTP.'),
  validator: (v) {
    if (v.contains(' ')) return 'Fill the whole OTP code';
    return null;
  },
  children: const [
    ShadInputOTPGroup(
      children: [
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
      ],
    ),
    Icon(size: 24, LucideIcons.dot),
    ShadInputOTPGroup(
      children: [
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
        ShadInputOTPSlot(),
      ],
    ),
  ],
)
```
