import 'package:equatable/equatable.dart';
import 'email_attachment.dart';

class ParsedEmail extends Equatable {
  final String from;
  final String to;
  final String cc;
  final String subject;
  final String date;
  final String textBody;
  final String htmlBody;
  final List<EmailAttachment> attachments;

  const ParsedEmail({
    required this.from,
    required this.to,
    this.cc = '',
    required this.subject,
    required this.date,
    required this.textBody,
    this.htmlBody = '',
    required this.attachments,
  });

  factory ParsedEmail.fromJS(Map<String, dynamic> json) {
    final headers = json['headers'] as Map<String, dynamic>? ?? {};
    final body = json['body'] as Map<String, dynamic>? ?? {};
    final attachmentsList = json['attachments'] as List<dynamic>? ?? [];

    return ParsedEmail(
      from: headers['from']?.toString() ?? '',
      to: headers['to']?.toString() ?? '',
      cc: headers['cc']?.toString() ?? '',
      subject: headers['subject']?.toString() ?? 'No Subject',
      date: headers['date']?.toString() ?? '',
      textBody: body['text']?.toString() ?? '',
      htmlBody: body['html']?.toString() ?? '',
      attachments: attachmentsList
          .map((att) => EmailAttachment.fromJS(att as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasHtmlBody => htmlBody.isNotEmpty;

  @override
  List<Object?> get props => [
        from,
        to,
        cc,
        subject,
        date,
        textBody,
        htmlBody,
        attachments,
      ];
}
