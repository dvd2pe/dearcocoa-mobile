import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dearcocoa/data/services/supabase_service.dart';

/// Small diagnostics sheet for the social layer (community / events / groups).
///
/// DearCocoa v0.3.3: when the feed or events fail to load, the user can open
/// "Diagnostica" next to the retry button and see the real cause (auth state,
/// Supabase host, the actual exception) plus a copy button for support.
Future<void> showSocialDebugSheet(
  BuildContext context, {
  required String area,
  Object? error,
}) {
  final signedIn = SupabaseService.instance.isSignedIn;
  String? userId;
  try {
    userId = SupabaseService.instance.client.auth.currentUser?.id;
  } catch (_) {
    userId = null;
  }
  String host;
  try {
    host = Uri.parse(SupabaseService.defaultUrl).host;
  } catch (_) {
    host = SupabaseService.defaultUrl;
  }

  final errorText = error?.toString() ?? '(no exception captured)';

  Widget row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor ?? const Color(0xFF1E293B),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report_outlined,
                    size: 18, color: Color(0xFF5B6CFF)),
                const SizedBox(width: 8),
                Text(
                  'Diagnostica — $area',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            row(
              'Sessione',
              signedIn ? 'attiva' : 'NON attiva (nessun login)',
              valueColor:
                  signedIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            ),
            row('User ID', userId == null ? '—' : userId),
            row('Supabase', host),
            const Divider(height: 20),
            const Text(
              'Errore reale:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                errorText,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB91C1C),
                    fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Suggerimenti: sessione non attiva → rifai il login; errore di '
              'rete → controlla la connessione; errore 4xx/5xx o schema → '
              'segnala il testo qui sopra.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: 'DearCocoa diagnostica $area\n'
                            'sessione: $signedIn\n'
                            'user: ${userId ?? '—'}\n'
                            'supabase: $host\n'
                            'errore: $errorText',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Diagnostica copiata')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copia'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5B6CFF),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Chiudi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
