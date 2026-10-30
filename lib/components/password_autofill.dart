import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Puts [child]'s password field in one autofill group with a hidden
/// username field holding [username], the wallet address, so a browser's
/// password manager offers to save the drive password for this account and
/// to fill it next time.
///
/// Flutter web builds one `<form>` per [AutofillGroup] with an input for
/// every field in it, each carrying its `autocomplete` attribute
/// (`AutofillHints.username` is `username`, `AutofillHints.password` is
/// `current-password`, `AutofillHints.newPassword` is `new-password`) and,
/// for a field without focus, its value. The username field is never shown
/// and never read by a screen reader; it only gives the saved password an
/// account to belong to.
///
/// The password field inside sets its own hint: `AutofillHints.password`
/// to enter one, `AutofillHints.newPassword` to set one. Call [save] once
/// the password is proven (the drive opened, the drive was made), which is
/// when a browser offers to save it. Closing the group otherwise saves
/// nothing, so a wrong password typed before Cancel is never offered.
class PasswordAutofillGroup extends StatefulWidget {
  const PasswordAutofillGroup({
    super.key,
    required this.username,
    required this.child,
  });

  final String username;
  final Widget child;

  /// Tells the browser the password in the group was used and worked.
  static void save() => TextInput.finishAutofillContext(shouldSave: true);

  @override
  State<PasswordAutofillGroup> createState() => _PasswordAutofillGroupState();
}

class _PasswordAutofillGroupState extends State<PasswordAutofillGroup> {
  late final _username = TextEditingController(text: widget.username);

  @override
  void didUpdateWidget(PasswordAutofillGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _username.text = widget.username;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Offstage(
            child: ExcludeSemantics(
              child: SizedBox(
                width: 1,
                height: 1,
                child: TextField(
                  key: const Key('passwordAutofillUsername'),
                  controller: _username,
                  readOnly: true,
                  enableInteractiveSelection: false,
                  autofillHints: const [AutofillHints.username],
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
