import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

class TbValidationMessages {
  static const invalidCode = 'invalidCode';
  static const tooManyRequests = 'tooManyRequest';
}

@Deprecated('Use TbValidationMessages instead.')
typedef TbValicationMessages = TbValidationMessages;

class TbTextField extends HookWidget {
  const TbTextField({
    super.key,
    this.hint = '',
    this.label = '',
    this.onSubmit,
    this.type,
    this.obscureText = false,
    this.autoFillHints,
    this.onMaxLengthReched,
    this.autoFocus = false,
    this.prefixIcon,
    this.suffixIcon,
    required this.formControlName,
    this.onPressed,
    this.readOnly = false,
  });

  final bool obscureText;
  final VoidCallback? onMaxLengthReched;
  final String hint;
  final String label;
  final VoidCallback? onSubmit;
  final String formControlName;
  final Iterable<String>? autoFillHints;
  final TextInputType? type;
  final bool autoFocus;
  final Widget? prefixIcon;
  final VoidCallback? onPressed;
  final Widget? suffixIcon;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final form = ReactiveForm.of(context) as FormControlCollection?;
    final node = useFocusNode();
    final formControl = form?.control(formControlName);
    final bool isRequired = (formControl?.validators ?? []).contains(
      Validators.required,
    );
    final MaxLengthValidator? maxLengthValidator =
        (formControl?.validators ?? [])
            .whereType<MaxLengthValidator>()
            .firstOrNull;

    final int? counterMaxValue = maxLengthValidator?.maxLength;
    final isVisible = useState(false);
    final isTouched = useRef(false);
    final isError = useRef(false);
    final isErrorState = useState(false);
    final counter = useState(0);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final errorColor = scheme.error;

    useEffect(() {
      void updateState() {
        isError.value = formControl?.invalid ?? false;
        isErrorState.value = isError.value && isTouched.value;
      }

      final errors = formControl?.statusChanged.listen((e) {
        isError.value = e == ControlStatus.invalid;
        updateState();
      });

      final touches = formControl?.touchChanges.listen((e) {
        isTouched.value = e;
        updateState();
      });
      return () {
        touches?.cancel();
        errors?.cancel();
      };
    }, [formControl?.statusChanged, formControl?.touchChanges]);

    return ReactiveTextField<dynamic>(
      focusNode: node,
      readOnly: readOnly,
      onTap: (control) {
        if (onPressed != null) {
          onPressed?.call();
          node.unfocus();
        }
      },
      onChanged: (control) {
        counter.value = control.value?.toString().length ?? 0;
        if (counter.value == counterMaxValue) {
          onMaxLengthReched?.call();
        }
      },
      autofocus: autoFocus,
      onSubmitted: (_) => onSubmit?.call(),
      maxLength: counterMaxValue,
      obscureText: obscureText && !isVisible.value,
      keyboardType: type,
      autofillHints: autoFillHints,
      formControlName: formControlName,
      validationMessages: {
        ValidationMessage.required: (error) => '$label is required.',
        ValidationMessage.email: (error) => 'Invalid email format.',
        ValidationMessage.mustMatch: (error) => 'Fields must match',
        ValidationMessage.minLength: (error) {
          final desc = error as Map;
          return '$label is too short, required length is ${desc['requiredLength']}';
        },
        ValidationMessage.maxLength: (error) {
          final desc = error as Map;
          return '$label is too long, required length is ${desc['requiredLength']}';
        },
        TbValidationMessages.tooManyRequests: (error) =>
            'Too many requests check verification code',
        TbValidationMessages.invalidCode: (error) =>
            'Invalid verification code format',
      },
      style: textTheme.bodyLarge?.copyWith(
        color: isErrorState.value ? errorColor : scheme.onSurface,
      ),
      decoration: InputDecoration(
        counterText: maxLengthValidator != null
            ? '${counter.value}/$counterMaxValue'
            : null,
        suffixIcon:
            suffixIcon ??
            (obscureText
                ? IconButton(
                    tooltip: isVisible.value
                        ? 'Hide password'
                        : 'Show password',
                    constraints: const BoxConstraints(
                      minWidth: DesignTokens.minTouchTarget,
                      minHeight: DesignTokens.minTouchTarget,
                    ),
                    icon: Icon(
                      !isVisible.value
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: scheme.onSurfaceVariant,
                      size: DesignTokens.iconMedium,
                    ),
                    onPressed: () {
                      isVisible.value = !isVisible.value;
                    },
                  )
                : null),
        prefixIcon: prefixIcon,
        labelText: isRequired ? '$label*' : label,
        hintText: hint,
        isDense: true,
        labelStyle: isErrorState.value
            ? textTheme.bodyLarge?.copyWith(color: errorColor)
            : null,
        floatingLabelStyle: isErrorState.value
            ? WidgetStateTextStyle.resolveWith((Set<WidgetState> states) {
                return (textTheme.labelSmall ?? const TextStyle()).copyWith(
                  color: errorColor,
                );
              })
            : null,
      ),
    );
  }
}
