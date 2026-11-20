import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thingsboard_democloud_app/config/themes/design_tokens.dart';

/// Material 3 debounced (`300ms`) search app bar with `>=48dp` actions.
class TbAppSearchBar extends StatefulWidget implements PreferredSizeWidget {
  TbAppSearchBar({
    super.key,
    this.elevation = 0,
    this.shadowColor,
    this.showLoadingIndicator = false,
    this.searchHint,
    this.onSearch,
    this.leading,
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : preferredSize = Size.fromHeight(
         kToolbarHeight + (showLoadingIndicator ? 4 : 0),
       );

  final double? elevation;
  final Color? shadowColor;
  final bool showLoadingIndicator;
  final String? searchHint;
  final void Function(String searchText)? onSearch;
  final Widget? leading;
  final Duration debounceDuration;

  @override
  final Size preferredSize;

  @override
  State<TbAppSearchBar> createState() => _TbAppSearchBarState();
}

class _TbAppSearchBarState extends State<TbAppSearchBar> {
  final TextEditingController _filter = TextEditingController();
  Timer? _debounce;
  String _lastDispatched = '';

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final current = _filter.text;
    if (current == _lastDispatched) return;
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      if (!mounted) return;
      _dispatch(current);
    });
  }

  void _dispatch(String query) {
    if (query == _lastDispatched) return;
    _lastDispatched = query;
    widget.onSearch?.call(query);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _filter.clear();
    _dispatch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filter.removeListener(_onTextChanged);
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          centerTitle: false,
          elevation: widget.elevation,
          shadowColor: widget.shadowColor,
          leadingWidth: widget.leading != null
              ? DesignTokens.minTouchTarget
              : null,
          leading: widget.leading,
          title: TextField(
            controller: _filter,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) {
              _debounce?.cancel();
              _dispatch(value);
            },
            style: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintStyle: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing8,
                vertical: DesignTokens.spacing12,
              ),
              hintText: widget.searchHint ?? 'Search',
            ),
          ),
          actions: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _filter,
              builder: (context, value, child) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Clear search',
                  constraints: const BoxConstraints(
                    minWidth: DesignTokens.minTouchTarget,
                    minHeight: DesignTokens.minTouchTarget,
                  ),
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSearch,
                );
              },
            ),
          ],
        ),
        if (widget.showLoadingIndicator) const LinearProgressIndicator(),
      ],
    );
  }
}
