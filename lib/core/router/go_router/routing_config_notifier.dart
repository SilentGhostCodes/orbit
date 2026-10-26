import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/custom_transition.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_page.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/features/profile/details/profile_details_page.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/overview/generic_list_page.dart';
import 'package:hiddify/features/route_rules/overview/package_names_page.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/features/settings/overview/sections/chain_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/dns_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/general_page.dart';
import 'package:hiddify/features/settings/overview/sections/inbound_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hiddify/features/settings/overview/sections/tls_tricks_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/orbit/home/orbit_home_page.dart';
import 'package:hiddify/orbit/servers/orbit_servers_page.dart';
import 'package:hiddify/orbit/settings/orbit_apps_page.dart';
import 'package:hiddify/orbit/settings/orbit_settings_page.dart';
import 'package:hiddify/orbit/shell/orbit_shell.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

// each branch in go router has its own focus scope
final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'profiles': FocusScopeNode(),
  'settings': FocusScopeNode(),
  'logs': FocusScopeNode(),
  'about': FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const Material())],
);

String getNameOfBranch(bool isMobileBreakpoint, bool showProfilesAction, int index) => isMobileBreakpoint
    ? ['home', 'settings'][index]
    : ['home', if (showProfilesAction) 'profiles', 'settings', 'logs', 'about'][index];

int getIndexOfBranch(bool isMobileBreakpoint, bool showProfilesAction, String name) => isMobileBreakpoint
    ? ['home', 'settings'].indexOf(name)
    : ['home', if (showProfilesAction) 'profiles', 'settings', 'logs', 'about'].indexOf(name);

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    if (isMobileBreakpoint == null) return loadingConfig;
    return RoutingConfig(
      redirect: (context, state) {
        // fix path-parameters for deep link
        String? url;
        if (LinkParser.protocols.contains(state.uri.scheme)) {
          // Android & iOS deep link
          url = state.uri.toString();
        } else if (PlatformUtils.isDesktop && newUrlFromAppLink.isNotEmpty) {
          // Desktops deep link
          url = newUrlFromAppLink;
          newUrlFromAppLink = '';
        } else if (state.uri.queryParameters['url'] != null) {
          // Get the configured URL for intro
          url = state.uri.queryParameters['url'];
        }

        if (state.matchedLocation == '/intro') {
          // Intro is completed
          // Current page in '/intro'
          if (url != null && Uri.parse(url).host == 'import') {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) =>
                  ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url, triggeredByDeepLink: true),
            );
          }
          return '/home';
        } else if (url != null && Uri.parse(url).host == 'import') {
          // Auto import profile from url
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(url: url, triggeredByDeepLink: true),
          );
          return '/home';
        } else if (url != null) {
          final uri = Uri.parse(url);
          final path = uri.path + (uri.hasQuery ? "?${uri.query}" : "");
          return path;
        } else if (state.matchedLocation.contains('chain-options') &&
            (ref.watch(hasAnyProfileProvider).value == false)) {
          // Prevent showing chainOptions while hasAnyProfile == false
          return '/settings';
        }
        return null;
      },
      routes: <RouteBase>[
        // Orbit: three tabs, with Hiddify's own settings pages kept under "Дополнительно".
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => OrbitShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => const OrbitHomePage(),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'profileDetails',
                      path: 'profile-details/:id',
                      pageBuilder: (_, state) => customTransition(
                        TransitionType.fade,
                        state.pageKey,
                        ProfileDetailsPage(id: state.pathParameters['id']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(name: 'servers', path: '/servers', builder: (_, _) => const OrbitServersPage()),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (_, _) => const OrbitSettingsPage(),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'orbitApps',
                      path: 'apps',
                      pageBuilder: (_, state) =>
                          customTransition(TransitionType.slide, state.pageKey, const OrbitAppsPage()),
                    ),
                    GoRoute(
                      name: 'logs',
                      path: 'logs',
                      pageBuilder: (_, state) => customTransition(TransitionType.slide, state.pageKey, const LogsPage()),
                    ),
                    GoRoute(
                      name: 'about',
                      path: 'about',
                      pageBuilder: (_, state) => customTransition(TransitionType.slide, state.pageKey, const AboutPage()),
                    ),
                    GoRoute(
                      name: 'advanced',
                      path: 'advanced',
                      pageBuilder: (_, state) => customTransition(TransitionType.slide, state.pageKey, SettingsPage()),
                      routes: <GoRoute>[
                        GoRoute(
                          name: 'general',
                          path: 'general',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const GeneralPage()),
                        ),
                        GoRoute(
                          name: 'routingOptions',
                          path: 'routing-options',
                          pageBuilder: (_, state) => customTransition(
                            TransitionType.slide,
                            state.pageKey,
                            RoutingOptionsPage(routeRule: state.uri.queryParameters['routeRule']),
                          ),
                          routes: <GoRoute>[
                            GoRoute(
                              name: 'rule',
                              path: 'rule/:orderId',
                              pageBuilder: (_, state) {
                                final orderIdString = state.pathParameters['orderId']!;
                                return customTransition(
                                  TransitionType.slide,
                                  state.pageKey,
                                  RulePage(ruleListOrder: orderIdString != 'new' ? int.tryParse(orderIdString) : null),
                                );
                              },
                              onExit: (context, state) async {
                                final t = ref.read(translationsProvider).requireValue;
                                final orderId = int.tryParse(state.pathParameters['orderId']!);
                                final isRuleEdited = ref.read(IsRuleEditedProvider(orderId));
                                if (orderId != null && isRuleEdited) {
                                  await ref.read(ruleNotifierProvider(orderId).notifier).save();
                                  ref
                                      .read(inAppNotificationControllerProvider)
                                      .showSuccessToast(t.common.msg.autoSave.success);
                                }
                                return true;
                              },
                              routes: <GoRoute>[
                                GoRoute(
                                  name: 'genericList',
                                  path: 'generic-list/:ruleEnum',
                                  pageBuilder: (_, state) {
                                    final orderId = int.tryParse(state.pathParameters['orderId']!);
                                    final ruleEnum = RuleEnum.values.byName(state.pathParameters['ruleEnum']!);
                                    return customTransition(
                                      TransitionType.slide,
                                      state.pageKey,
                                      GenericListPage(ruleListOrder: orderId, ruleEnum: ruleEnum),
                                    );
                                  },
                                ),
                                GoRoute(
                                  name: 'packageNames',
                                  path: 'package-names',
                                  pageBuilder: (_, state) => customTransition(
                                    TransitionType.slide,
                                    state.pageKey,
                                    PackageNamesPage(ruleListOrder: int.tryParse(state.pathParameters['orderId']!)),
                                  ),
                                ),
                              ],
                            ),
                            GoRoute(
                              name: 'appList',
                              path: 'app-list',
                              pageBuilder: (_, state) =>
                                  customTransition(TransitionType.slide, state.pageKey, const AppListPage()),
                            ),
                          ],
                        ),
                        GoRoute(
                          name: 'dnsOptions',
                          path: 'dns-options',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const DnsOptionsPage()),
                        ),
                        GoRoute(
                          name: 'inboundOptions',
                          path: 'inbound-options',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const InboundOptionsPage()),
                        ),
                        GoRoute(
                          name: 'tlsTricks',
                          path: 'tls-tricks',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const TlsTricksPage()),
                        ),
                        GoRoute(
                          name: 'chainOptions',
                          path: 'chain-options',
                          pageBuilder: (_, state) =>
                              customTransition(TransitionType.slide, state.pageKey, const ChainOptionsPage()),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        // Hiddify's names for pages Orbit replaced, so its widgets still land somewhere sensible
        GoRoute(name: 'proxies', path: '/proxies', redirect: (_, _) => '/servers'),
        GoRoute(name: 'profiles', path: '/profiles', redirect: (_, _) => '/home'),
        GoRoute(name: 'intro', path: '/intro', redirect: (_, _) => '/home'),
      ],
    );
  }
}
