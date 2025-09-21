import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class OwnerField extends StatefulWidget {
  final String? ownerAddress;

  const OwnerField({
    super.key,
    required this.ownerAddress,
  });

  @override
  State<OwnerField> createState() => _OwnerFieldState();
}

class _OwnerFieldState extends State<OwnerField> {
  String? _arnsName;
  String? _arnsLogo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.ownerAddress != null) {
      _loadArnsName();
    }
  }

  Future<void> _loadArnsName() async {
    if (!mounted || widget.ownerAddress == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final arnsRepository = context.read<ARNSRepository>();
      final primaryName = await arnsRepository.getPrimaryName(
        widget.ownerAddress!,
        getLogo: true,
      );

      if (mounted) {
        setState(() {
          _arnsName = primaryName.primaryName;
          // Check for both null and "null" string
          _arnsLogo = (primaryName.logo != null && primaryName.logo != 'null')
              ? primaryName.logo
              : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      // If ArNS lookup fails, just show the address
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openArnsLink() {
    if (_arnsName != null) {
      final configService = context.read<ConfigService>();
      String gateway =
          configService.config.defaultArweaveGatewayUrl ?? 'ardrive.net';
      gateway =
          gateway.replaceFirst('https://', '').replaceFirst('http://', '');
      openUrl(url: 'https://$_arnsName.$gateway');
    }
  }

  void _openViewBlockLink() {
    if (widget.ownerAddress != null) {
      openUrl(
          url: 'https://viewblock.io/arweave/address/${widget.ownerAddress}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ownerAddress == null) {
      return const SizedBox.shrink();
    }

    final colors = ArDriveTheme.of(context).themeData.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo if available
        if (_arnsLogo != null &&
            _arnsLogo!.isNotEmpty &&
            _arnsLogo != 'null') ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              _arnsLogo!.startsWith('http')
                  ? _arnsLogo!
                  : 'https://ardrive.net/$_arnsLogo',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // Name or address - styled like transaction IDs
        Flexible(
          child: ArDriveClickArea(
            child: GestureDetector(
              onTap: _arnsName != null ? _openArnsLink : _openViewBlockLink,
              child: _isLoading
                  ? SizedBox(
                      width: 60,
                      height: 16,
                      child: LinearProgressIndicator(
                        backgroundColor: colors.themeBgSurface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            colors.themeAccentBrand),
                      ),
                    )
                  : ArDriveTooltip(
                      message: _arnsName != null
                          ? 'ar://$_arnsName'
                          : widget.ownerAddress!,
                      child: Text(
                        _arnsName != null
                            ? () {
                                // Show more characters when no logo is present
                                final maxChars = (_arnsLogo == null ||
                                        _arnsLogo!.isEmpty ||
                                        _arnsLogo == 'null')
                                    ? 16 // More space available without logo
                                    : 8; // With logo, show 8 chars
                                return _arnsName!.length > maxChars
                                    ? 'ar://${_arnsName!.substring(0, maxChars)}...'
                                    : 'ar://$_arnsName';
                              }()
                            : '${widget.ownerAddress!.substring(0, 4)}...',
                        style: ArDriveTypography.body
                            .buttonNormalRegular()
                            .copyWith(
                              decoration: TextDecoration.underline,
                            ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
            ),
          ),
        ),

        // Copy button - always copies wallet address
        const SizedBox(width: 12),
        CopyButton(
          text: widget.ownerAddress!,
        ),

        // External link icon for ViewBlock (only when ArNS name is shown)
        if (_arnsName != null) ...[
          const SizedBox(width: 8),
          ArDriveClickArea(
            tooltip: 'View on ViewBlock',
            child: GestureDetector(
              onTap: _openViewBlockLink,
              child: ArDriveIcons.newWindow(
                size: 20,
                color: colors.themeFgDefault,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
