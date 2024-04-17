import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory icons() {
  return WidgetbookCategory(
    name: 'Icons',
    children: [
      WidgetbookComponent(
        name: 'Icons',
        useCases: [
          WidgetbookUseCase(
            name: 'Icons',
            builder: (context) {
              return ArDriveStorybookAppBase(builder: (context) {
                return ListView.builder(
                  itemCount: _options.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: _options[index].icon,
                      title: Text(_options[index].name,
                          style: ArDriveTypography.body.buttonNormalBold()),
                    );
                  },
                );
              });
            },
          ),
        ],
      ),
    ],
  );
}

// TODO: we may want to generate this list from the icons.dart file
List<IconOption> _options = [
  IconOption(icon: ArDriveIcons.iconAddDrive(), name: 'iconAddDrive'),
  IconOption(icon: ArDriveIcons.iconNewFolder1(), name: 'iconNewFolder1'),
  IconOption(icon: ArDriveIcons.iconUploadFolder1(), name: 'iconUploadFolder1'),
  IconOption(icon: ArDriveIcons.iconUploadFiles(), name: 'iconUploadFiles'),
  IconOption(
      icon: ArDriveIcons.iconCreateSnapshot(), name: 'iconCreateSnapshot'),
  IconOption(icon: ArDriveIcons.iconAttachDrive(), name: 'iconAttachDrive'),
  IconOption(icon: ArDriveIcons.arconnectIcon1(), name: 'arconnectIcon1'),
  IconOption(icon: ArDriveIcons.addDrive(), name: 'addDrive'),
  IconOption(icon: ArDriveIcons.arrowLeftFilled(), name: 'arrowLeftFilled'),
  IconOption(icon: ArDriveIcons.arrowLeftOutline(), name: 'arrowLeftOutline'),
  IconOption(icon: ArDriveIcons.arrowLeft(), name: 'arrowLeft'),
  IconOption(icon: ArDriveIcons.arrowRightFilled(), name: 'arrowRightFilled'),
  IconOption(icon: ArDriveIcons.arrowRightOutline(), name: 'arrowRightOutline'),
  IconOption(icon: ArDriveIcons.bullertList(), name: 'bullertList'),
  IconOption(icon: ArDriveIcons.camera1(), name: 'camera1'),
  IconOption(icon: ArDriveIcons.camera2(), name: 'camera2'),
  IconOption(icon: ArDriveIcons.carretDown(), name: 'carretDown'),
  IconOption(icon: ArDriveIcons.carretLeft(), name: 'carretLeft'),
  IconOption(icon: ArDriveIcons.carretRight(), name: 'carretRight'),
  IconOption(icon: ArDriveIcons.carretUp(), name: 'carretUp'),
  IconOption(icon: ArDriveIcons.checkCirle(), name: 'checkCirle'),
  IconOption(icon: ArDriveIcons.checkmark(), name: 'checkmark'),
  IconOption(icon: ArDriveIcons.closeCircle(), name: 'closeCircle'),
  IconOption(icon: ArDriveIcons.closeRectangle(), name: 'closeRectangle'),
  IconOption(icon: ArDriveIcons.copy(), name: 'copy'),
  IconOption(icon: ArDriveIcons.dots(), name: 'dots'),
  IconOption(icon: ArDriveIcons.download(), name: 'download'),
  IconOption(icon: ArDriveIcons.editFilled(), name: 'editFilled'),
  IconOption(icon: ArDriveIcons.edit(), name: 'edit'),
  IconOption(icon: ArDriveIcons.fileX(), name: 'fileX'),
  IconOption(icon: ArDriveIcons.file(), name: 'file'),
  IconOption(icon: ArDriveIcons.fileOutlined(), name: 'fileOutlined'),
  IconOption(icon: ArDriveIcons.folderFilled(), name: 'folderFilled'),
  IconOption(icon: ArDriveIcons.folderOutline(), name: 'folderOutline'),
  IconOption(icon: ArDriveIcons.upload(), name: 'upload'),
  IconOption(icon: ArDriveIcons.triangle(), name: 'triangle'),
  IconOption(icon: ArDriveIcons.menu(), name: 'menu'),
  IconOption(icon: ArDriveIcons.refresh(), name: 'refresh'),
  IconOption(icon: ArDriveIcons.x(), name: 'x'),
  IconOption(icon: ArDriveIcons.newWindow(), name: 'newWindow'),
  IconOption(icon: ArDriveIcons.share(), name: 'share'),
  IconOption(icon: ArDriveIcons.license(), name: 'license'),
  IconOption(icon: ArDriveIcons.move(), name: 'move'),
  IconOption(icon: ArDriveIcons.plus(), name: 'plus'),
  IconOption(icon: ArDriveIcons.tournament(), name: 'tournament'),
  IconOption(icon: ArDriveIcons.logout(), name: 'logout'),
  IconOption(icon: ArDriveIcons.user(), name: 'user'),
  IconOption(icon: ArDriveIcons.zip(), name: 'zip'),
  IconOption(icon: ArDriveIcons.question(), name: 'question'),
  IconOption(icon: ArDriveIcons.image(), name: 'image'),
  IconOption(icon: ArDriveIcons.video(), name: 'video'),
  IconOption(icon: ArDriveIcons.music(), name: 'music'),
  IconOption(icon: ArDriveIcons.info(), name: 'info'),
  IconOption(icon: ArDriveIcons.kebabMenu(), name: 'kebabMenu'),
  IconOption(icon: ArDriveIcons.eyeClosed(), name: 'eyeClosed'),
  IconOption(icon: ArDriveIcons.eyeOpen(), name: 'eyeOpen'),
  IconOption(icon: ArDriveIcons.keypad(), name: 'keypad'),
  IconOption(icon: ArDriveIcons.pinNoCircle(), name: 'pinNoCircle'),
  IconOption(icon: ArDriveIcons.pinWithCircle(), name: 'pinWithCircle'),
  IconOption(icon: ArDriveIcons.arrowDownload(), name: 'arrowDownload'),
  IconOption(icon: ArDriveIcons.cloudSync(), name: 'cloudSync'),
  IconOption(icon: ArDriveIcons.detach(), name: 'detach'),
  IconOption(icon: ArDriveIcons.download2(), name: 'download2'),
  IconOption(icon: ArDriveIcons.manifest(), name: 'manifest'),
];

class IconOption {
  final ArDriveIcon icon;
  final String name;

  const IconOption({
    required this.icon,
    required this.name,
  });
}
