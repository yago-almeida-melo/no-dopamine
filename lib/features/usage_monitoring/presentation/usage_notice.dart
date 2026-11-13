import 'package:flutter/material.dart';

class UsageNotice extends StatelessWidget {
  const UsageNotice(
      {required this.icon,
      required this.title,
      required this.description,
      this.action,
      super.key});
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(height: 1.5)),
                if (action != null) ...[const SizedBox(height: 16), action!],
              ],
            )),
      );
}
