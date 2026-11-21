# Changelog

## v0.9.5 (2026-11-22)

**Features**

- **mitm** Modules can now route rules through exits and rule-set providers. (7158fe0)
- **ios** Mirror the on-demand SSID direct override onto the App core so the status card and service status show direct results (581d898)
- **dashboard** Set the default dashboard cards to status, network speed, VPN switch, outbound mode, service status, connections, proxy groups, profiles and traffic statistics. (cc64d33)
- **ios** The MITM settings follow the upstream options layout, and a trusted certificate can be removed so the Core generates a fresh one on restart. (ac90aeb)
- **probe** Restore the upstream probe scheduling with proxied from the host state. (95ab9ff)
- **proxies** Show the leaf-node count on the node folder tab and tighten the folder bar insets (980111f)
- **proxies** Rename the Icons proxy style to Cards (b4f5249)
- **proxies** Proxies page: a Leaf Nodes tab, nodes-only sorting, an opaque top bar, test-all in every style, larger group icons, and Icons/compact/plain are now the defaults; the traffic overview gauge is centred (f2f14a3)
- **proxies** Proxies grid: capsule folder tabs, in-group search, live speeds for the selected node, member group icons, and sorting that moves only node groups. (72d59a3)
- **proxies** Add an Icons style to the proxies page with full-width expanded groups, Zashboard-style group headers, folder tabs, and sort, size and icon style support (eb45c21)
- **traffic** Traffic statistics now ranks by policy group and egress node, and the rule ranking is removed. (41b198a)
- **proxies** Add a Zashboard-style icon grid for proxy groups, with brand icons and a delay pill on each card. (7cdb7b5)
- **traffic** Open traffic statistics in a half sheet, add a clear-statistics action, and center the overview gauge. (aab8695)
- **dashboard** Remove the Global connections globe card from the dashboard (72f8006)
- **traffic** Show four grid cells in the month traffic trend. (a2e0dff)
- **traffic** Show four grid cells in the week traffic trend. (a1f827b)
- **traffic** Traffic trend bars are now the same thin width in every range. (1d14035)
- **traffic** Traffic overview: remove the gauge inner disc, center the gauge on the total figure, and merge proxy/direct back into one cell. (785af93)
- **traffic** Traffic trend charts show vertical dashed gridlines in day, week and month views (a740c37)
- **traffic** Traffic statistics uptime label goes back to its original style (e13b332)
- **traffic** Rule hit cards show hits and traffic on a single smaller line (b202dab)
- **traffic** Traffic statistics overview card matches the Stash layout (352db89)
- **traffic** Rule hit type tags use theme colors, with Match sharing RuleSet's fill (9e0ade7)
- **traffic** Fix traffic statistics trend axis labels wrapping, thin out trend bars, unfill rule type tags, and show full rule hit counts. (2fe9b6c)
- **dashboard** Add a dashboard card that shows Zashboard's global-connections globe in place. (9835460)
- **traffic** Move the rule ranking tab after domain and align the traffic statistics page closer to the Stash layout. (741620e)
- **traffic** Restyle the traffic statistics page and dashboard card after the Stash layout, drop the process ranking tab, add tunnel uptime tracking, date paging, and a rule ranking tab. (6b66345)
- Add a traffic statistics page with day, week and month views, including totals, trends, rule hits and rankings, plus a dashboard card for today's traffic. (4ffb730)
- **ios** A new 'Loopback 10.7.0.1' switch in the TUN section reflects 10.7.0.1 back to this device, so SideStore and SideInstaller can reach it while the VPN is on. (89aa066)
- **mitm** Loon conditional mock_file rewrites now load as Map Local entries (3f7aedf)
- **core** Update the core to mihomo v1.19.34 (FlClash branch) (386ea64)
- **mitm** MITM scripts can now answer requests directly with $done({response}) and the engine identifies itself as Surge to scripts (0c21866)
- **mitm** Added MITM script execution for HTTP requests and responses, $persistentStore/$prefs, $httpClient, $notification, $network and cron scheduling. (85ad7a0)
- **config** Changed the default system proxy setting to off. (21b5dcf)
- **config** Moved the outbound section from the network page to below the inbound section on the general page. (bfa174d)
- **config** Moved the virtual network interface section above the include-all-networks section on the network page. (06f2079)
- **config** Added a DNS hijack list to the TUN section and made the TCP keep-alive settings available on iOS. (5f102fb)
- **config** Move the VPN block to the top of the network page. (10268d3)
- **config** Move the TUN section above the VPN section on the network page. (66eb922)
- **ios** Hide the allow-bypass switch on iOS, where the packet tunnel has no per-app bypass API. (8156818)
- **config** Add the remaining TUN engine switches (disable ICMP forwarding, endpoint independent NAT, batch receive/send, UDP timeout) to the TUN section. (f9fdc2c)
- **config** Show the TUN stack picker in the TUN section instead of the options section (efa2dfa)
- **ios** Show the iOS include-all-networks switches in their own section instead of mixed into the VPN section (4f82aee)
- **ios** Add iOS-only VPN switches for include-all-networks plus the local-network, APN, cellular-service, route-enforcement and device-communication exclusions (ef97d26)
- **ios** Show a restart banner when MITM settings change or the certificate becomes trusted, and give the restart button tap feedback (ff2ca0b)
- **codemagic** Builds now publish automatically to the v0.9.3-ios release. (8046afc)
- **probe** Dashboard probes no longer wait 5 seconds before falling back to the App core when 9090 does not answer. (79bc845)
- **ios** The dashboard status, service status and outbound IP now stay working while the tunnel is up. (5738548)
- **ios** Dashboard outbound IP now reads from the extension core over 9090 instead of the broken XPC channel. (ed38845)
- **ios** MITM page now reads captures from the extension core over 9090 instead of the broken XPC channel. (1b58ae2)
- **ios** The service card's route check now goes through the external controller first. (b23f4f5)
- **ios** The external controller is now always on, and its secret no longer changes. (f97b130)
- **ios** 9090-first dashboard, proxy, and delay paths no longer fall back to XPC; they go straight to the App core when the controller is unreachable, and delay tests now run through 9090 first. (8b469b7)
- **ios** The bundled Zashboard web panel is back on the dashboard, opening at 127.0.0.1:9090/ui. (709cb95)
- **ios** When the VPN tunnel fails to start, the error banner now names the reason (invalid configuration, disabled configuration, extension failure, or tunnel never started) instead of showing the raw system error. (6705497)
- **l10n** Error banners now show translated messages for core start, stop, transport, session and lifecycle failures instead of the raw English error. (f82811c)
- **dashboard** The dashboard memory card now also shows the extension core's memory on iOS, so the total covers the VPN tunnel too. (6182f03)
- **ios** iOS: keep the extension event queue inside the shared FlClash folder, so the App Group root holds only that folder. (7c364d9)
- **ios** iOS: keep app data in the app's private directory and share only the tunnel profile and MITM files with the VPN extension, so the app stays alive in the background. (9561fef)
- **mitm** MITM body-rewrite and map-local now take effect on decrypted traffic. (b3cccdd)
- **mitm** MITM module scripts (cron, event and generic) now actually run, with their logs and result shown. (9df4941)
- **ios** On-demand connection (per-SSID direct/disconnect) is back. (dcf3359)
- **ios** The core can now run without turning on the VPN switch. (b4ba2c6)
- **ios** Error banners are now shown in Simplified Chinese. (eff52af)
- **mitm** MITM captures now read from the extension core first, with the external controller and the app core as fallbacks (a152fdc)
- **ios** Live features now read from the extension core first, with the external controller and the app core as fallbacks. (037e17a)
- **ssid** Direct-mode SSIDs now switch the core to direct from the extension itself, and the mode is restored even if the controller is briefly unreachable. (83912b4)
- **mitm** MITM captures now show in-flight exchanges live while the tunnel runs, as well as the persisted history after it stops. (f55dd39)
- **mitm** MITM captures are now readable from the app over the controller as well as from the shared disk. (567da5d)
- Added a setting to hide the environment watermark (PRE/DEBUG ribbon) in the top-right corner. (4be4f13)
- **ssid** Newly added excluded SSIDs now default to Direct instead of Disconnect. (28b22c3)
- **ssid** The Exclude SSIDs cards now animate like the swipe actions on LiveContainer's subscription proxy page, close when you tap or swipe elsewhere, and show the SSID name and status centered. (3495798)
- **on-demand** Add per-SSID actions for excluded Wi-Fi networks: swipe left for direct mode, right to disconnect (ef444b5)
- **on-demand** Excluded SSIDs now suspend the VPN on iOS (5f1ae6d)
- **mitm** MITM captures are now stored on disk instead of in the extension's memory, so heavy capture sessions no longer push the VPN tunnel toward its memory limit; decrypted hosts and requests stay visible after the tunnel stops. (8586826)
- **core** Add HTTPS decryption (MITM) to the core using the open-source mitmproxy-go engine. (2ca67dd)
- **ios** Forward LAN TCP to the loopback proxy so LAN sharing works with loopback-only bind (216a7eb)
- **ios** Read dashboard data from the 9090 external controller with Router fallback (64bb9dc)
- **ios** Forward app core listeners to the extension on port+1 (6def8d9)

**Bug Fixes**

- **tun** TUN settings are saved with the Core's key names; existing settings carry over. (77977a7)
- **ios** Fix the spurious "config is not applied" banner on an on-demand cold start. (12aa5f6)
- **ui** The environment watermark follows the theme color. (eab6dc8)
- **dashboard** Restarting the core from the live-status deck starts a stopped core. (ed9765e)
- **dashboard** Show the live-status button when the core stops. (9b6f3cf)
- **service** Service detection is no longer pinned to the App core, so it is answered by the core that is actually routing. (e114fac)
- **ios** Cold start with the tunnel already on no longer shows the 7890 bind error (6c5f4b1)
- **proxies** Proxies page: the top bar stays translucent in the list style and solid in the card style (71ace08)
- **service** Service detection probes each service through its own node instead of the tunnel, so services show their own IPs (e2fe64f)
- **ios** On iOS, stopping the Core now waits for the tunnel to release the listener ports before the App core starts its own listeners, so the Mixed listener no longer fails with address already in use. (af2de32)
- **ios** On iOS, stopping the Core first hands the listeners back to the App core so the address returns to the local IP, then stops the App core. (8c7884b)
- **ios** Start the App core listeners before the extension on iOS, then hand them over once the tunnel is up. (319977e)
- **vpn** Restarting from a settings banner now re-applies the profile, so the changed settings reach the tunnel (d303d5c)
- **proxies** Proxies page: the top bar is translucent again; scrolled content shows through it (ad6ce08)
- **config** Fix the TUN stack picker showing twice on the network page on mobile. (1dff909)
- **proxies** Speed up manual delay tests by running 32 at once, matching upstream. (db320ff)
- **proxies** Keep the delay pill neutral while a test runs, and show the folder bar only in the card style. (5b975c7)
- **probe** Fix service detection showing a single IP for all services while the tunnel is up on iOS. (a2e1934)
- **proxies** Stretch the proxy folder tabs to fill the full row, aligned with the group cards below. (5552356)
- **traffic** Lower the traffic overview gauge to sit 12 dp below the title row. (2c4b09a)
- **traffic** Raise the traffic overview gauge to the top of the card, level with the title row. (d1040d8)
- **traffic** Centre the traffic overview gauge on the total traffic block so the gaps above and below it are even. (43c5c62)
- **ios** The Loopback 10.7.0.1 switch now actually turns reflection in the core on and off. (37b8eb5)
- **ios** The TUN congestion controller, UDP timeout and DNS hijack list now reach the iOS core; they were silently dropped before. (58cd453)
- **ios** The 'App core applied the config, but the extension core did not receive it' banner no longer appears. (9f2dd71)
- **ios** Excluded SSIDs now switch to rule mode instead of disconnecting the VPN (210da81)
- **ios** Dashboard mode segment now shows the mode the routing core actually runs, so an SSID override no longer leaves it showing the configured mode (f9a7e65)
- **ios** Remove the popup banner shown when the tunnel fails to start (2f897a7)
- **ios** Log tunnel start failures at warning level instead of info level (8894ca8)
- **ios** Log tunnel start failures at info level instead of error level (2c796cd)
- **core** Fix the tunnel failing to start from the iOS VPN switch when the saved config path is unreadable (bb6b4d9)
- **ios** Report a tunnel start failure even when iOS tears the tunnel down through the disconnecting state. (fb650ab)
- **ios** A tunnel start that fails without the app driving it now leaves a failure report in the log. (b5d2a91)
- **ios** Fix the mixed-port bind failure when turning the VPN switch off while the tunnel is stopping. (7a3dec9)
- **ios** An external VPN stop now also stops the core. (eb702a9)
- **l10n** Localized the Hosts title and the close-connections error title. (89ff87c)
- **ios** Exporting the MITM certificate on iOS now asks first, and only opens the share sheet after confirming (f0f5e00)
- **ios** Install the MITM certificate through Safari and export it through the share sheet (2bba87e)
- **ios** Include enabled MITM modules' IPs and domains in the system proxy exception list (d81e3b8)
- **mitm** MITM module rules with ^ anchors now match as intended. (bc812c0)
- **mitm** The MITM option switches now take effect: Block QUIC, HTTP/2, and decrypt when untrusted. (f6ece7f)
- **ios** Replace the default system-proxy bypass list with private ranges and local suffixes (d390130)
- **ios** Route MITM hosts around the system proxy so the tunnel captures them (2cf0b5d)
- **ios** Drop the extension push failure banner; silence it on profile switch (1364810)
- **ios** Pin node delay tests to the App core (3cfc637)
- **ios** Sync node selection and mode to the App core so the status and service cards follow them (2d5f4b8)
- **ios** Rerun probes when the VPN options come back after a cold restart (87ef8d9)
- **ios** Retry the 9090 outbound-IP lookup while its answer is unusable (dbb245f)
- **ios** Wait for the 9090 listener before the first probe round and queue manual refreshes (6b33d0b)
- **ios** Report disconnecting instead of connecting while the tunnel stops (90a92f6)
- **core** Fix MITM capture not showing with the system proxy on by always rebuilding the mixed listener with the MITM-wrapped tunnel. (1eb7b11)
- **ios** the local controller is now reached directly even with the system proxy on. (c359933)
- **ios** the running flag now re-syncs when the app reopens with the tunnel already up. (5c563a8)
- **requests** MITM labels on the Requests page now update live as new captures arrive. (fca2593)
- **mitm** Fixed MITM decryption not working while the system proxy is on. (23a26a6)
- **ios** Fixed the dashboard, delay test, and Zashboard card going dead after swiping the app away and reopening it while the VPN was on. (7b83dcf)
- **ios** Dashboard detection now recovers after returning to the app instead of staying failed until the next settings change. (e85cd10)
- **ios** the extension now picks up the latest config on tunnel restarts instead of a stale saved copy. (b9e86cd)
- **ios** relaunching the app no longer stops a running tunnel when the extension misses a config push. (e755f23)
- **ios** clearing the DNS cache now works while the tunnel is running. (96b6203)
- **ios** identical consecutive DNS log entries now collapse into one row with a count badge. (5e30a01)
- **ios** detection waits longer for the extension controller to come up before falling back. (776ef85)
- **ios** detection retries the extension controller once when the tunnel is still starting, instead of failing at once. (36d1a45)
- **mitm** MITM now decrypts whenever it is switched on. (085786e)
- **ios** Reopening the app no longer switches off a running tunnel. (42efcf2)
- **ios** Fixed the tunnel being switched off when reopening the app after swiping it away. (a41287b)
- **ios** Config changes now reach the extension core over 9090 first, so mode and port changes apply even when the extension channel does not answer. (a0e27bc)
- **ios** The dashboard and proxy selection now prefer the local 9090 controller over the extension channel, wait 30 seconds before retrying a silent extension call, and log which call went unanswered. (db0b197)
- **ios** The traffic poll now waits a minute before retrying the extension after an empty response, instead of retrying every second. (9937788)
- **ios** The "extension core did not receive the config" banner now shows the actual failure reason in your language instead of a generic error. (0c27553)
- **dashboard** The dashboard memory card no longer counts the App Core's memory twice on iOS, so its total now matches the real usage. (a0f841c)
- **ios** Fixed proxy selection falling back to the previous node when the tunnel control channel was unreachable; the selection now reaches the extension through its controller as well. (bfe06e0)
- **ios** Dashboard traffic and memory now fall back to the app core when both the extension and the 9090 controller are unreachable. (9863f54)
- **ios** Connections, request counts, and the Requests live feed now fall back to the app core when both the tunnel channel and the 9090 controller are unreachable, instead of showing an error. (c5cc817)
- **ios** Requests page keeps its 9090 fallback for live connections. (0e3b0fc)
- **ios** Flipping the VPN switch while running now starts or stops just the tunnel on iOS, without restarting the core. (60bd001)
- **mitm** MITM copy, export, and detail loading now fall back to the external controller and the app core when the extension does not answer (a244b7d)
- **ios** Fix app-side detection: proxy delays, service status, route checks and DNS cache clearing now fall back to the extension core over 9090 when the app-to-extension message channel fails. (1921289)
- **ssid** Fixed leaving a direct-mode Wi-Fi network while the controller was briefly unreachable permanently sticking in direct mode, and the app now recognizes an already-connected excluded Wi-Fi network on cold start. (5d80992)
- **core** Fix MITM interception: TLS connections through the VPN tunnel are now actually inspected and decrypted when their host is in the MITM list. (7db93e4)
- **mitm** MITM header rewrites work, changing the mixed port no longer breaks decrypted connections until restart, and capture limits behave as shown. (98ac5a4)
- **mitm** MITM changes now show a tunnel restart prompt, and the core logs the applied MITM state (fbf7c72)
- **mitm** MITM no longer silently truncates request or response bodies over 1 MiB, and turning the capture switch off now really stops recording while decrypted-connection markers keep showing. (e49cb1f)
- **mitm** Fixed the MITM certificate export failing on iOS and the CA always showing as not installed after installing and trusting it. (68ff185)
- **core** Fixed the tunnel failing to start on the build with the MITM engine: the wrapper now forwards the provider interface the TUN listener requires. (abf5aa0)
- **ios** Tunnel start no longer reads stale config, restarting the core on iOS works again, and mode/proxy sync failures now warn and retry instead of silently diverging. (6379afa)
- **ios** Fix service detection and other extension calls failing with "empty response" after a tunnel restart by retrying on a freshly loaded tunnel session. (9b8f62c)
- **ios** Harden iOS App Group shared-state handling: torn-write detection with fallback to the previous state, clearer errors when the tunnel config fails to stage or the shared container cannot be found, and re-migration of newer data files. (3baa0df)
- **ios** Read the App Group from the containing app bundle in extensions (36cc8b3)
- **ios** Discover the App Group from the provisioning profile (0d85026)
- **ios** Retry a missed reply from the VPN extension once before failing, and stop the Zashboard panel from opening onto a login page when the controller secret is out of sync. (34c1682)
- **ios** Read the dashboard live-connection count from 9090 first (35c60b3)
- **ios** Default the required VPN options instead of failing decode (7e6853c)
- **ios** Honor onlyStatisticsProxy for the 9090 traffic path (aa4c8e1)
- **ios** Skip the 9090 selection sync when the tunnel is down (62c8ef2)
- **ios** Close connections through the 9090 controller when VPN is on (40955ff)
- **ios** Read Requests live feed from the 9090 external controller first (36bf55a)
- **ios** Mark the throwing NWListener initializer with try (fb3de2b)
- **ios** Propagate proxy group selection to the 9090 external controller (5ed99ed)
- **ios** Keep the dashboard connections list when one entry is malformed (162c9f2)
- **ios** Exclude loopback from the tunnel so the system proxy reaches the local core (2fe28c1)
- **ios** Stop the app core from binding the external controller (c912e74)
- **ios** Stop the app core from binding the external controller (8b6a105)
- **ios** Let the app core own the mixed port, extension skips it (19e0405)
- **ios** Stop the app core from binding the mixed port (a0e0dd8)
- **ios** Stop the app core from binding the DNS listen port (d3fac27)
- **ios** Link the core and the VPN switch like Android (8732859)
- **ios** Let the tunnel start from Settings without the app (bcaa2c8)
- **core** Drop provider cache paths outside the core home directory (efc052c)
- **ios** Surface the extension's real tunnel error (5a70f8b)
- **core** Use the profile as-is when the base has no overlay (20a7882)
- **ios** Forward the built config when the profile has no base (c6ba237)
- **ios** Carry the profile base in the shared state so the tunnel can start (7a0068a)
- **ios** Report whether start options were sent on tunnel failure (8cb6363)
- **ios** Forward tunnel config through startVPNTunnel options (1e5bd23)
- Clear external-ui-name so mihomo stops trying to download the web UI (665d8e5)
- **ios** Surface the real tunnel state and tunnel start failures (1c2c977)
- **ios** CoreLib must exist on iOS, not only Android (374f16a)
- Await migrateIOSDataDirectory inside try in path.dart (98957f0)

**Reverts**

- **ios** Restore the author's error log and banner for tunnel start failures. (2d55cb4)
- **service** Restore the upstream service detection with the main-line probe scheduling. (822a60b)
- **probe** Restore the main-line probe scheduling. (95f1c47)
- **service** Restore the main-line service detection while keeping the new probe scheduling. (4fb7aa7)
- **service** Restore the App-core pin for the service status check. (752d102)
- Excluded SSIDs disconnect the VPN again instead of switching to rule mode (ec93be2)
- **core** Revert the core to mihomo 024245dc. (c88af80)
- **ios** An external VPN stop no longer stops the core. (8050b70)
- **ios** Restore status-card and service detection to the branch start, keep the probes (724c756)
- Drop the MITM listener rebuild and the disconnecting state (08ba7a4)
- **ios** Removed the per-SSID direct/disconnect actions and the non-dashboard 9090 fallbacks; the dashboard keeps its extension-controller chain. (ed84554)
- **ios** Read dashboard connections table from the App core again (9a3098f)

## v0.9.4 (2026-11-19)

**Features**

- **dashboard** One status button gathers core, update and resource states, with counts, download progress and new card icons (a89b339)
- **rules** Added rules can go to named custom exits; a profile's script and added rules run together and open from the extend page (c8b34f2)
- **proxy** PAC mode for the desktop system proxy; new Windows installs bypass <local>; GTK apps on KDE Plasma follow the proxy (7633c3c)
- **dns** respect-rules, hosts and cache-algorithm in the DNS overrides; macOS system DNS through tun.dns-mode native (ca2693a)
- **logs** Open a log on a phone to select and copy it (c85bf3a)
- **resources** Geo resources update automatically by default (1b2ea11)
- **desktop** Impeller on Windows and Intel Macs; the Apple Silicon download no longer carries Intel code (848583d)
- Update the core to mihomo v1.19.34, with editor completion for its new keys (e57e5ac)

**Bug Fixes**

- **core** A start that fails or a lost Core says why; a mixed port of 0 is replaced; the mixed port opens without a profile (8298573)
- **config** Process rules match by default; picked override keys are written as set, empty included (044f5b5)
- **android** WireGuard, Hysteria2 and TUIC reconnect after a network change; core sockets opened before the VPN are protected (b13cf52)
- **dashboard** Service and exit IP checks no longer fail while the proxy starts, stops or changes network (408aaa9)
- **core** HTTPUpgrade share links no longer import as WebSocket (47824d4)
- **connections** App icons show whenever the app is known and keep their place while loading (5c5964f)
- **desktop** macOS tray windows stay on the current Space; windows use the target display's scale; AppImage without a bundled libstdc++; cleaner deb removal; the Windows installer only stops its own processes (c620dc9)
- **ui** Pages open at the top and on the selected profile; sheets open from sheets as pages; the editor shows its spinner and grows its sheet; calmer success and warning colors; remote icons hold their size (b08bcd9)

**Performance**

- **connections** Connections rank and sort off the UI thread; proxy and group icons use less memory (19fb1b0)

## v0.9.3 (2026-11-04)

**Features**

- **connections** Merged requests and connections; quick edit lists (52b975f)
- **ui** iOS 27 transitions, press and text selection; smoother pages (bb47f2c)
- **update** Download and install updates in the app (b8f84b3)
- **core** One delay test timeout; VPN crash and startup fixes (2a5a42c)

**Bug Fixes**

- **core** Auto-select leaves an unusable first node at once (7d5db7e)
- **access** Keep selections a filter hides (63aaf6d)

## v0.9.2 (2026-10-24)

**Features**

- **access** Access control state shown in a bar at the bottom (e8aac17)
- **config** Optional general overrides; settings apply sooner (5d6552d)
- **dashboard** IP quality cached for 3 days; simpler Android dashboard (8176cce)
- Update the core to mihomo v1.19.33 (0817c3b)
- **tray** Colored tray status icons; monochrome option on macOS (bbfafde)
- **desktop** Sidebar blur; Windows fixes; keeps system proxies FlClash didn't set (6928521)
- **profiles** Profile QR codes, phone-to-TV links, more proxy fields (eaaf3e3)
- **proxies** Add proxies to local proxies; adjustable delay test timeout (0f9f89c)
- **theme** Higher-contrast dark mode and a refreshed app icon (a4fc067)
- **ui** iOS-style docked search and menus; bar buttons lift on hover (0d98a9d)
- **ui** iOS-style switches, stretchy sheets, menus and long-press reordering (ae902ed)
- **ui** Pages scroll under the Android navigation bar (4837fb3)
- **core** Clear the DNS cache by hand or on network change (09e7e56)

**Bug Fixes**

- **android** Opening the app no longer reloads a running VPN (99b3381)

**Performance**

- **editor** Smoother editor for large files and in sheets (7035edd)

## v0.9.1 (2026-10-17)

**Breaking Changes**

- **network** Desktop TUN keys follow the profile unless picked; changed values carry over (cb08088)

**Features**

- **l10n** French, Spanish and Korean translations (f43755c)
- **android** No more Firebase analytics or crash reporting (bc72bba)
- **network** Per-key desktop TUN settings; system proxy and tray fixes (cb08088)
- **theme** Redesigned theme colors and color styles (5eafd7a)
- **dashboard** A redesigned dashboard around the current exit (9bd258f)
- **profiles** Profile-detail resources and include-all in custom groups (0bac500)
- **proxies** Proxy groups as cards, group tabs as chips (2ea52fd)
- **views** Sortable tables for connections, requests and DNS (da6fb0a)
- **ui** Optional two-tier Liquid Glass and slide-to-pick menus (7c9627f)
- **ui** iOS-style surfaces, alerts and sheets; clearer TV focus (9bd2286)

**Bug Fixes**

- **ui** Fix pasting and Chinese input in text fields (5607f70)
- **core** Large profiles no longer crash; downloads trust core CAs (5984c16)

**Performance**

- **android** Smoother Android UI while the proxy is busy (2201c19)

## v0.9.0 (2026-10-14)

**Breaking Changes**

- **views** DNS and NTP override toggles are removed; picked keys apply to every profile (491fae1)
- **database** Custom overwrites are removed; rebuild them as custom profiles (1677024)

**Features**

- **views** Per-key DNS, NTP, sniffer and TUN settings (491fae1)
- **profiles** Custom profiles (3abda78)
- **ui** Stacked sheets, context menus and a sort mode (8c43053)
- **providers** DNS, Hosts and ports apply without a restart (532ebf0)
- **android** Launcher shortcuts and one-step on-demand access (d3fa225)
- **core** Share link import and mrs rule sets (2fa2f7f)

**Bug Fixes**

- **database** Unreadable settings no longer block startup or restores (1677024)
- **desktop** Windows and Linux desktop fixes (94a25f4)
- **core,helper** The elevated Core only answers its owner (d780cb8)

## v0.8.99 (2026-10-03)

**Features**

- **editor** Editor word wrap and snippets (e131675)
- **dashboard** More dashboard cards (e62afb7)
- **views** Hide timed-out nodes and search every list (8378c70)
- **ui** Sidebar, floating dock and drag to go back (841d603)
- **ui** New app glyphs, empty states and theme page (ee6a497)
- **overwrite** Invalid override warnings and rule presets (46fb7fe)
- **config** DNS query log and per-key DNS/NTP overrides (a390a42)
- **core** Proxied service checks and outbound IP risk (8068e68)
- **platform** Tray hotkeys, node delays and a delay test (1e97716)

**Bug Fixes**

- **core** A changed resource link is now used by the next sync and by auto update (ff23f30)
- **core** DNS lookups no longer fail on networks that report no DNS servers (e55f6d1)
- **proxies** Smaller icons in icon-only group headers (786a6ab)
- **core,android** Push notifications reconnect in Doze (1e9955d)
- **backup,database** Restores never apply halfway (bee8f24)

## v0.8.98 (2026-09-14)

**Bug Fixes**

- **resources** Refresh the geo file size and time after an update finishes (c5bf5bd)
- **core** Keep the core running while Windows sleeps with the app suspended (60f371a)

## v0.8.97 (2026-09-10)

**Features**

- **ui** Rework the app UI and refresh the localization (26cfbaf)
- **app** Rework the app layer and window handling, and add proxy authentication (aaf934c)
- **desktop** Rework the desktop runners, packaging, and native build (c0fcbc0)
- **android** Rework the Android VPN service and lifecycle handling (ae29f38)
- **plugins** Rework the desktop plugins and add the Helper service and Rust bridge (adf715f)
- **core** Rework the core IPC and process lifecycle (c6eaa0a)

<!-- changelog:frozen -->
<!-- Entries below predate the structured pipeline. Their wording is kept as written; only the heading and list style were normalized. -->

## v0.8.96 (2026-08-17)

- Optimize commented policy
- Fix whole group delay test failing on Windows
- Optimize package icon loading and connections polling

## v0.8.95 (2026-08-14)

- Optimize core service
- Optimize Android TV launcher icon
- Optimize back navigation
- Optimize more details
- Fix some issues
- Optimize app layout
- Optimize focus control
- Adjust android process

## v0.8.94 (2026-07-11)

- Fix macos performance issue
- Support custom global-ua
- Update core
- Optimize some details
- Fix linux silent launching not working

## v0.8.93 (2026-05-29)

- Support custom overwrite
- Support run on demand
- Optimize windows ipc
- Optimize windows arm64
- Optimize build
- Optimize some details
- Update core

## v0.8.92 (2026-02-02)

- Add sqlite store
- Optimize android quick action
- Optimize backup and restore
- Optimize more details

## v0.8.91 (2025-12-12)

- Fix windows some issues
- Optimize overwrite handle
- Optimize access control page
- Optimize some details

## v0.8.90 (2025-10-08)

- Fix android tile service
- Support append system DNS
- Fix some issues
- Update changelog

## v0.8.89 (2025-09-27)

- Fix some issues
- Optimize Windows service mode
- Update core
- Update changelog

## v0.8.88 (2025-09-23)

- Add android separates the core process
- Support core status check and force restart
- Optimize proxies page and access page
- Update flutter and pub dependencies
- Update go version
- Optimize more details
- Update changelog

## v0.8.87 (2025-07-29)

- Optimize desktop view
- Optimize logs, requests, connection pages
- Optimize windows tray auto hide
- Optimize some details
- Update core
- Update changelog

## v0.8.86 (2025-06-15)

- Fix windows tun issues
- Optimize android get system dns
- Optimize more details
- Update changelog

## v0.8.85 (2025-06-07)

- Support override script
- Support proxies search
- Support svg display
- Optimize config persistence
- Add some scenes auto close connections
- Update core
- Optimize more details

## v0.8.84 (2025-05-01)

- Fix windows service verify issues
- Update changelog

## v0.8.83 (2025-05-01)

- Add windows server mode start process verify
- Add linux deb dependencies
- Add backup recovery strategy select
- Support custom text scaling
- Optimize the display of different text scale
- Optimize windows setup experience
- Optimize startTun performance
- Optimize android tv experience
- Optimize default option
- Optimize computed text size
- Optimize hyperOS freeform window
- Add developer mode
- Update core
- Optimize more details
- Add issues template
- Update changelog

## v0.8.82 (2025-04-18)

- Optimize android vpn performance
- Add custom primary color and color scheme
- Add linux nad windows arm release
- Optimize requests and logs page
- Fix map input page delete issues
- Update changelog

## v0.8.81 (2025-04-08)

- Add rule override
- Update core
- Optimize more details
- Update changelog

## v0.8.80 (2025-03-10)

- Optimize dashboard performance
- Fix some issues
- Fix unselected proxy group delay issues
- Fix asn url issues
- Update changelog

## v0.8.79 (2025-03-07)

- Fix tab delay view issues
- Fix tray action issues
- Fix get profile redirect client ua issues
- Fix proxy card delay view issues
- Add Russian, Japanese adaptation
- Fix some issues
- Update changelog

## v0.8.78 (2025-03-05)

- Fix list form input view issues
- Fix traffic view issues
- Update changelog

## v0.8.77 (2025-03-05)

- Optimize performance
- Update core
- Optimize core stability
- Fix linux tun authority check error
- Fix some issues
- Fix scroll physics error
- Update changelog

## v0.8.75 (2025-02-09)

- Add windows storage corruption detection
- Fix core crash caused by windows resource manager restart
- Optimize logs, requests, access to pages
- Fix macos bypass domain issues
- Update changelog

## v0.8.74 (2025-02-03)

- Fix some issues
- Update changelog

## v0.8.73 (2025-02-02)

- Update popup menu
- Add file editor
- Fix android service issues
- Optimize desktop background performance
- Optimize android main process performance
- Optimize delay test
- Optimize vpn protect
- Update changelog

## v0.8.72 (2025-01-10)

- Update core
- Fix some issues
- Update changelog

## v0.8.71 (2025-01-09)

- Remake dashboard
- Optimize theme
- Optimize more details
- Update flutter version
- Update changelog

## v0.8.70 (2024-12-09)

- Support better window position memory
- Add windows arm64 and linux arm64 build script
- Optimize some details

## v0.8.69 (2024-12-06)

- Remake desktop
- Optimize change proxy
- Optimize network check
- Fix fallback issues
- Optimize lots of details
- Update change.yaml
- Fix android tile issues
- Fix windows tray issues
- Support setting bypassDomain
- Update flutter version
- Fix android service issues
- Fix macos dock exit button issues
- Add route address setting
- Optimize provider view
- Update changelog
- Update CHANGELOG.md

## v0.8.67 (2024-11-09)

- Add android shortcuts
- Fix init params issues
- Fix dynamic color issues
- Optimize navigator animate
- Optimize window init
- Optimize fab
- Optimize save

## v0.8.66 (2024-10-26)

- Fix the collapse issues
- Add fontFamily options

## v0.8.65 (2024-10-26)

- Update core version
- Update flutter version
- Optimize ip check
- Optimize url-test

## v0.8.64 (2024-10-12)

- Update release message
- Init auto gen changelog
- Fix windows tray issues
- Fix urltest issues
- Add auto changelog
- Fix windows admin auto launch issues
- Add android vpn options
- Support proxies icon configuration
- Optimize android immersion display
- Fix some issues
- Optimize ip detection
- Support android vpn ipv6 inbound switch
- Support log export
- Optimize more details
- Fix android system dns issues
- Optimize dns default option
- Fix some issues
- Update readme

## v0.8.60 (2024-09-17)

- Fix build error2
- Fix build error
- Support desktop hotkey
- Support android ipv6 inbound
- Support android system dns
- fix some bugs

## v0.8.59 (2024-09-09)

- Fix delete profile error

## v0.8.58 (2024-09-08)

- Fix submit error 2
- Fix submit error
- Optimize DNS strategy
- Fix the problem that the tray is not displayed in some cases
- Optimize tray
- Update core
- Fix some error

## v0.8.57 (2024-09-02)

- Fix tun update issues
- Add DNS override
- Fixed some bugs
- Optimize more detail
- Add Hosts override

## v0.8.56 (2024-08-26)

- fix android tip error
- fix windows auto launch error

## v0.8.55 (2024-08-25)

- Fix windows tray issues
- Optimize windows logic
- Optimize app logic
- Support windows administrator auto launch
- Support android close vpn

## v0.8.53 (2024-08-15)

- Change flutter version
- Support profiles sort
- Support windows country flags display
- Optimize proxies page and profiles page columns

## v0.8.52 (2024-08-11)

- Update flutter version
- Update version
- Update timeout time
- Update access control page
- Fix bug

## v0.8.51 (2024-08-05)

- Optimize provider page
- Optimize delay test
- Support local backup and recovery
- Fix android tile service issues

## v0.8.49 (2024-07-31)

- Fix linux core build error
- Add proxy-only traffic statistics
- Update core
- Optimize more details
- Merge pull request #140 from txyyh/main
- 添加自建 F-Droid 仓库相关 workflow
- Rename readme fingerprint
- Rename workflow deploy repo name
- Add download guide to README
- Add push release files to fdroid-repo

## v0.8.48 (2024-07-25)

- Optimize proxies page
- Fix ua issues
- Optimize more details

## v0.8.47 (2024-07-22)

- Fix windows build error

## v0.8.46 (2024-07-22)

- Update app icon
- Fix desktop backup error
- Optimize request ua
- Change android icon
- Optimize dashboard

## v0.8.44 (2024-07-18)

- Remove request validate certificate
- Sync core

## v0.8.43 (2024-07-18)

- Fix windows error

## v0.8.42 (2024-07-18)

- Fix setup.dart error
- Fix android system proxy not effective
- Add macos arm64

## v0.8.41 (2024-07-17)

- Optimize proxies page
- Support mouse drag scroll
- Adjust desktop ui
- Revert "Fix android vpn issues"
- This reverts commit 891977408e6938e2acd74e9b9adb959c48c79988.

## v0.8.40 (2024-07-15)

- Fix android vpn issues
- Fix android vpn issues
- Rollback partial modification

## v0.8.39 (2024-07-15)

- Fix the problem that ui can't be synchronized when android vpn is occupied by an external
- Override default socksPort,port

## v0.8.38 (2024-07-14)

- Fix fab issues

## v0.8.37 (2024-07-14)

- Update version
- Fix the problem that vpn cannot be started in some cases
- Fix the problem that geodata url does not take effect

## v0.8.36 (2024-07-13)

- Update ua
- Fix change outbound mode without check ip issues
- Separate android ui and vpn
- Fix url validate issues 2
- Add android hidden from the recent task
- Add geoip file
- Support modify geoData URL

## v0.8.35 (2024-07-07)

- Fix url validate issues
- Fix check ip performance problem
- Optimize resources page

## v0.8.34 (2024-07-04)

- Add ua selector
- Support modify test url
- Optimize android proxy
- Fix the error that async proxy provider could not selected the proxy

## v0.8.33 (2024-07-01)

- Fix android proxy error
- Fix submit error
- Add windows tun
- Optimize android proxy
- Optimize change profile
- Update application ua
- Optimize delay test

## v0.8.32 (2024-06-28)

- Fix android repeated request notification issues

## v0.8.31 (2024-06-28)

- Fix memory overflow issues

## v0.8.30 (2024-06-27)

- Optimize proxies expansion panel 2
- Fix android scan qrcode error

## v0.8.29 (2024-06-27)

- Optimize proxies expansion panel
- Fix text error

## v0.8.28 (2024-06-26)

- Optimize proxy
- Optimize delayed sorting performance
- Add expansion panel proxies page
- Support to adjust the proxy card size
- Support to adjust proxies columns number
- Fix autoRun show issues
- Fix Android 10 issues
- Optimize ip show

## v0.8.26 (2024-06-22)

- Add intranet IP display
- Add connections page
- Add search in connections, requests
- Add keyword search in connections, requests, logs
- Add basic viewing editing capabilities
- Optimize update profile

## v0.8.25 (2024-06-19)

- Update version
- Fix the problem of excessive memory usage in traffic usage.
- Add lightBlue theme color
- Fix start unable to update profile issues
- Fix flashback caused by process

## v0.8.23 (2024-06-16)

- Add build version
- Optimize quick start
- Update system default option

## v0.8.22 (2024-06-16)

- Update build.yml
- Fix android vpn close issues
- Add requests page
- Fix checkUpdate dark mode style error
- Fix quickStart error open app
- Add memory proxies tab index
- Support hidden group
- Optimize logs
- Fix externalController hot load error

## v0.8.21 (2024-06-13)

- Add tcp concurrent switch
- Add system proxy switch
- Add geodata loader switch
- Add external controller switch
- Add auto gc on trim memory
- Fix android notification error

## v0.8.20 (2024-06-12)

- Fix ipv6 error
- Fix android udp direct error
- Add ipv6 switch
- Add access all selected button
- Remove android low version splash

## v0.8.19 (2024-06-10)

- Update version
- Add allowBypass
- Fix Android only pick .text file issues

## v0.8.18 (2024-06-09)

- Fix search issues

## v0.8.17 (2024-06-09)

- Fix LoadBalance, Relay load error
- Fix build.yml4
- Fix build.yml3
- Fix build.yml2
- Fix build.yml
- Add search function at access control
- Fix the issues with the profile add button to cover the edit button
- Adapt LoadBalance and Relay
- Add arm
- Fix android notification icon error

## v0.8.16 (2024-06-08)

- Add one-click update all profiles
- Add expire show

## v0.8.15 (2024-06-06)

- Temp remove tun mode
- Remove macos in workflow
- Change go version

## v0.8.14 (2024-06-06)

- Update Version
- Fix tun unable to open

## v0.8.13 (2024-06-06)

- Optimize delay test2
- Optimize delay test
- Add check ip
- add check ip request

## v0.8.12 (2024-06-06)

- Fix the problem that the download of remote resources failed after GeodataMode was turned on, which caused the
  application to flash back.
- Fix edit profile error
- Fix quickStart change proxy error
- Fix core version

## v0.8.10 (2024-06-05)

- Fix core version

## v0.8.9 (2024-06-05)

- Update file_picker
- Add resources page
- Optimize more detail
- Add access selected sorted
- Fix notification duplicate creation issue
- Fix AccessControl click issue

## v0.8.7 (2024-05-31)

- Fix Workflow
- Fix Linux unable to open
- Update README.md 3
- Create LICENSE
- Update README.md 2
- Update README.md
- Optimize workFlow

## v0.8.6 (2024-05-31)

- optimize checkUpdate

## v0.8.5 (2024-05-30)

- Fix submit error

## v0.8.4 (2024-05-30)

- add WebDAV
- add Auto check updates
- Optimize more details
- optimize delayTest

## v0.8.2 (2024-05-15)

- upgrade flutter version

## v0.8.1 (2024-05-15)

- Update kernel
- Add import profile via QR code image

## v0.8.0 (2024-05-11)

- Add compatibility mode and adapt clash scheme.

## v0.7.14 (2024-05-07)

- update Version
- Reconstruction application proxy logic

## v0.7.13 (2024-05-06)

- Fix Tab destroy error

## v0.7.12 (2024-05-06)

- Optimize repeat healthcheck

## v0.7.11 (2024-05-06)

- Optimize Direct mode ui

## v0.7.10 (2024-05-06)

- Optimize Healthcheck
- Remove proxies position animation, improve performance
- Add Telegram Link
- Update healthcheck policy
- New Check URLTest
- Fix the problem of invalid auto-selection

## v0.7.8 (2024-05-05)

- New Async UpdateConfig
- add changeProfileDebounce
- Update Workflow
- Fix ChangeProfile block
- Fix Release Message Error

## v0.7.7 (2024-05-04)

- Update Selector 2

## v0.7.6 (2024-05-04)

- Update Version
- Fix Proxies Select Error

## v0.7.5 (2024-05-03)

- Fix the problem that the proxy group is empty in global mode.
- Fix the problem that the proxy group is empty in global mode.

## v0.7.4 (2024-05-03)

- Add ProxyProvider2

## v0.7.3 (2024-05-03)

- Add ProxyProvider
- Update Version
- Update ProxyGroup Sort
- Fix Android quickStart VpnService some problems

## v0.7.1 (2024-05-01)

- Update version
- Set Android notification low importance
- Fix the issue that VpnService can't be closed correctly in special cases
- Fix the problem that TileService is not destroyed correctly in some cases
- Adjust tab animation defaults
- Add Telegram in README_zh_CN.md
- Add Telegram

## v0.7.0 (2024-04-30)

- update mobile_scanner
- Initial commit
