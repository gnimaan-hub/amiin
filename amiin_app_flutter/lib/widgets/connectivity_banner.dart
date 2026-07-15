import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../theme/themes.dart';
import '../theme/typography.dart';

class ConnectivityBanner extends StatelessWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: connectivityService,
      child: Column(
        children: [
          Consumer<ConnectivityService>(
            builder: (context, svc, _) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: svc.isOnline ? 0 : 32,
                color: context.ac.alertColor,
                child: svc.isOnline
                    ? const SizedBox()
                    : Center(
                        child: Text(
                          'Pas de connexion internet',
                          style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: context.ac.onAccent),
                        ),
                      ),
              );
            },
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

