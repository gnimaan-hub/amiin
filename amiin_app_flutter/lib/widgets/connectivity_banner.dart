import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../theme/colors.dart';
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
                color: ColorsAmiin.corail,
                child: svc.isOnline
                    ? const SizedBox()
                    : Center(
                        child: Text(
                          'Pas de connexion internet',
                          style: TextStyle(
                            fontFamily: FontFamily.geoMedium,
                            fontSize: 12,
                            color: ColorsAmiin.white,
                          ),
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


