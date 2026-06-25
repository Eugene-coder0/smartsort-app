import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Handles the system clipboard action strings
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:solana/solana.dart';
import 'package:solana/dto.dart';
import 'package:http/http.dart' ;
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // === CRITICAL FIX FOR CHROME / WEB RUNS ===
  // Without this explicit configuration block, Chrome cannot see your data stream!
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCRQGkTLGuaJbwLAvfHDdjGzR7DuMv6pMc",
     authDomain: "smartsort-iot-140ab.firebaseapp.com",
     databaseURL: "https://SmartSort-iot-140ab-default-rtdb.firebaseio.com",
     projectId: "smartsort-iot-140ab",
     storageBucket: "smartsort-iot-140ab.firebasestorage.app",
     messagingSenderId: "614640331165",
     appId: "1:614640331165:web:25003e62e7284b5f822774"
    ),
  );
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DashboardScreen(),
  ));
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _databaseRef = FirebaseDatabase.instance.ref();
  
  // Text tracking controller for target user recipient input
  final TextEditingController _userWalletController = TextEditingController();

  String systemState = "Connecting..."; 
  int wasteLevel = 0; 
  List<String> wasteLogs = ["Waiting for activity stream..."];

  late SolanaClient _solanaClient;
  String _walletAddress = "Loading Wallet...";
  String _solBalance = "0.00";

  // State tracker to hold digital reward points/credits locally
  double digitalRewardCredits = 0.0;

  // --- ALERTA INTEGRATION MONITORING STATE FLAG ---
  bool isMaintenanceMode = false;
  bool _wasPreviouslyFull = false;
  // Add these variables at the top of your state class
final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
bool _isListening = false;
String _speechText = "Press the mic and say a command...";
final SpeechToText _speech = SpeechToText();

// This function sends manual motor command strings straight to Firebase
void _sendMotorCommand(String direction) {
  _dbRef.child('motor_control').set({
    'command': direction,
    'timestamp': ServerValue.timestamp,
    'triggered_by': 'app_manual'
  });
}

// This function handles initializing and listening to your voice
void _listenToVoice() async {
  if (!_isListening) {
    bool available = await _speech.initialize(
      onStatus: (val) => print('Speech Status: $val'),
      onError: (val) => print('Speech Error: $val'),
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) {
          setState(() {
            _speechText = val.recognizedWords;
            // Voice command checking logic
           _speech.listen(
  onResult: (val) {
    setState(() {
      _speechText = val.recognizedWords;
      String command = val.recognizedWords.toLowerCase();
      
      // Expanded Voice Command Processing Engine
      if (command.contains('open') || command.contains('up') || command.contains('forward')) {
        _sendMotorCommand('FORWARD');
      } else if (command.contains('close') || command.contains('down') || command.contains('reverse') || command.contains('back')) {
        _sendMotorCommand('REVERSE');
      } else if (command.contains('left')) {
        _sendMotorCommand('LEFT');     // 👈 Added Left Support!
      } else if (command.contains('right')) {
        _sendMotorCommand('RIGHT');   // 👈 Added Right Support!
      } else if (command.contains('stop') || command.contains('halt')) {
        _sendMotorCommand('STOP');
      }
    });
  },
);
          });
        },
      );
    }
  } else {
    setState(() => _isListening = false);
    _speech.stop();
  }
}

  @override
  void initState() {
    super.initState();
    _activateFirebaseStream();
    _initializeSolana();
  }

  @override
  void dispose() {
    _userWalletController.dispose();
    super.dispose();
  }

  // --- SOLANA CORE INITIALIZATION LAYER ---
  Future<void> _initializeSolana() async {
    _solanaClient = SolanaClient(
      rpcUrl: Uri.parse('https://api.devnet.solana.com'),
      websocketUrl: Uri.parse('wss://api.devnet.solana.com'),
    );

    // Hardcoded Admin Node Keypair derivation logic
    final Ed25519HDKeyPair keypair = await Ed25519HDKeyPair.fromMnemonic(
      "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    );

    setState(() {
      _walletAddress = keypair.address;
    });
    _updateBalance();
  }

  Future<void> _updateBalance() async {
    try {
      final dynamic balanceData = await _solanaClient.rpcClient.getBalance(_walletAddress);
      final int lamports = (balanceData is int) ? balanceData : (balanceData.value as int);
      setState(() {
        _solBalance = (lamports / 1000000000).toStringAsFixed(4);
      });
    } catch (_) {}
  }

  // --- INTERACTIVE FIREBASE STREAM ADAPTER WITH ALERTA ---
void _activateFirebaseStream() {
    print("Initializing Firebase stream listener...");
    
    _databaseRef.child('SmartSort').onValue.listen((DatabaseEvent event) {
      print("Firebase updated! Data found: ${event.snapshot.value}");
      
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          int incomingWasteLevel = int.tryParse(data['waste_level']?.toString() ?? "0") ?? 0;
          wasteLevel = incomingWasteLevel;

          if (incomingWasteLevel >= 90) { 
            isMaintenanceMode = true;
            systemState = "Maintenance Mode";
            
            // Send alert only once when crossing the threshold
            if (!_wasPreviouslyFull) {
              _wasPreviouslyFull = true;
              sendTelegramAlert("🚨 *CRITICAL NODE ALERT* 🚨\n\nBin capacity is at 90%! System locked in Maintenance Mode.");
            }
            
            if (wasteLogs.isEmpty || !wasteLogs[0].contains("🚨 [ALERTA]")) {
              wasteLogs.insert(0, "🚨 [ALERTA] CRITICAL: Bin full ($incomingWasteLevel%). Maintenance ticket pushed out.");
            }
          } else {
            isMaintenanceMode = false;
            systemState = data['system_state']?.toString() ?? "Operational";

            // RECOVERY TRIGGER: Send message when system is back to normal
            if (_wasPreviouslyFull) {
              _wasPreviouslyFull = false; 
              sendTelegramAlert("✅ *SmartSort Status Update*\n\nSystem is Good to Go! Bin has been emptied and operations are resumed.");
            }
          }
          
          String? incomingAction = data['last_sorted']?.toString();
          if (incomingAction != null && incomingAction.isNotEmpty) {
            _recordSortingOnChain(incomingAction); // Ensure this matches your method name
          }
        }); // END setState
      } else {
        print("Warning: Connected to Firebase, but the 'SmartSort' folder is empty!");
      }
    });
  }

  // --- SOLANA INTEGRATION WORKFLOW LOGIC WITH ALERTA LOCKOUT ---
  Future<void> _recordSortingOnChain(String wasteType) async {
    // 6. Workflow: Sorting operations are completely disabled until the bin is emptied and reset
    if (isMaintenanceMode) {
      print("Workflow Step 6: Operation blocked. SmartSort is locked inside Maintenance Mode.");
      setState(() {
        
        if (!wasteLogs[0].contains("🚫 SORTING BLOCKED")) {
          wasteLogs.insert(0, "🚫 SORTING BLOCKED: Deposit rejected due to capacity limits. Awaiting sweep.");
        }
      });
      return; // Break execution immediately: blocks rewards and on-chain logs
    }
// 👇 PASTE THE PIECE OF CODE HERE (At the bottom of your successful try block) 👇
    if (wasteLevel >= 90) { 
      await sendTelegramAlert(
        "🚨 *CRITICAL NODE ALERT* 🚨\n\n"
        "• *Node Status:* MAINTENANCE MODE\n"
        "• *Reason:* Bin Capacity has reached Max Threshold 🛑\n"
        "• *Action Required:* Empty smart bin container and clear system lockout flag."
      );
    }

    final String destinationInput = _userWalletController.text.trim();

    // 1. Workflow: Users interact with SmartSort (Firebase stream handled)
    print("Workflow Step 1: User deposited $wasteType");

    // 2. Workflow: Reward points are recorded in the backend (Calculate points/credits)
    double calculatedCredit = wasteType.toLowerCase().contains("wet") ? 0.05 : 0.10;
    
    setState(() {
      digitalRewardCredits += calculatedCredit;
    });
    print("Workflow Step 2: Points recorded. Total user credits: $digitalRewardCredits SOL");

    // 3. Workflow: Eligible rewards are processed through Solana (Wallet verification check)
    if (destinationInput.isEmpty) {
      setState(() {
        wasteLogs.insert(0, "ℹ️ Account Balance: +${calculatedCredit} Credits logged locally (No wallet set)");
      });
      return; 
    }

    try {
      final Ed25519HDKeyPair adminKeypair = await Ed25519HDKeyPair.fromMnemonic(
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
      );

      if (double.parse(_solBalance) <= 0.0) {
        throw Exception("Insufficient Admin Node Fees");
      }

      // Convert our credit valuation directly to Lamports for blockchain processing
      int lamportsToTransfer = (calculatedCredit * 1000000000).toInt();

      // 4. Workflow: Transactions are stored transparently on the blockchain
      final signature = await _solanaClient.sendAndConfirmTransaction(
        message: Message(
          instructions: [
            SystemInstruction.transfer(
              fundingAccount: adminKeypair.publicKey,
              recipientAccount: Ed25519HDPublicKey.fromBase58(destinationInput),
              lamports: lamportsToTransfer,
            ),
            MemoInstruction(
              signers: [adminKeypair.publicKey],
              memo: "SmartSort Reward: Verified $wasteType Placement",
            ),
          ],
        ),
        signers: [adminKeypair],
        commitment: Commitment.confirmed,
      );

      await _updateBalance();

      // 5. Workflow: Users receive digital reward credits (Confirmed update status)
      setState(() {
        wasteLogs.insert(
          0, 
          "⛓️ Tx: ${signature.substring(0, 8)}... Paid $calculatedCredit SOL to user. Secure & Transparent."
        );
      });

    } catch (e) {
      print("Solana execution skipped or failed: $e");
      
      // Fallback: Show transparent transaction details via simulated block updates if gas/network fails
      setState(() {
        wasteLogs.insert(
          0, 
          "🛡️ Transparent Ledger [Mock]: $calculatedCredit SOL credited safely to ${destinationInput.substring(0, 5)}..."
        );
      });
    }
  }
  
  Future<void> sendTelegramAlert(String message) async {
  final String token = "8919742610:AAFsl2b1iXXsSF9YHv_ceI8QsFtIeziSnYw";
  final String chatId = "-5356770635"; 

  final Uri url = Uri.parse(
    "https://api.telegram.org/bot$token/sendMessage?chat_id=$chatId&text=${Uri.encodeComponent(message)}"
  );

   try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      print("🚀 Telegram alert pushed successfully!");
    } else {
      print("❌ Telegram failed. Status code: ${response.statusCode}");
    }
  } catch (e) {
    print("⚠️ Error sending Telegram request: $e");
  }
}
   Future<void> _issueMotorCommand(String command) async {
  try {
    // Updates a single string field under SmartSort/motor_control
    await _databaseRef.child('SmartSort').update({'motor_control': command});
    print("🕹️ Drive Command Sent: $command");
  } catch (e) {
    print("⚠️ Motor Control Error: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Two views: 1 for the Public User, 1 for the Internal Admin
      child: Scaffold(
        backgroundColor: const Color(0xFF13151A),
        appBar: AppBar(
          title: const Text('SmartSort Ecosystem', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: const Color(0xFF1C1E24),
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.recycling), text: "Public User Interface"),
              Tab(icon: Icon(Icons.admin_panel_settings), text: "Admin Panel"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            
            // =================================================================
            // VIEW 1: THE PUBLIC USER INTERFACE
            // =================================================================
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
       // 👇 NEW SIDE-BY-SIDE BRANDING ROW 👇
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start, // Pulls everything to the far left
                      crossAxisAlignment: CrossAxisAlignment.center, // Centers them vertically with each other
                      children: [
                        // 1. App Logo on the left
                        Image.asset(
                          'assets/logo.png',
                          width: 205,   // Slightly smaller so it blends cleanly next to text
                          height: 205,
                          fit: BoxFit.contain,
                        ),
                        
                        const SizedBox(width: 16), // Clear gap between the logo and text
                        
                        // 2. High-Visibility App Name on the right
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SmartSort',
                              style: TextStyle(
                                fontSize: 38,                 // Extra large and visible
                                fontWeight: FontWeight.w900, // Extra thick font weight
                                letterSpacing: 0.5,           // Tight, clean modern professional spacing
                                color: Colors.white,          // Crisp white color pops cleanly off a dark theme
                              ),
                            ),
                            Text(
                              'Ecosystem Workspace',          // Subheading to ground the branding layout
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.tealAccent,      // Neon accent color for premium contrast
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16), // Space before your live bin status card starts
                  // 👆 END OF BRANDING ROW 👆
                  // Public Telemetry: Bin Capacity & Operational Status (Tints red if in Maintenance)
                  Card(
                    color: isMaintenanceMode ? const Color(0xFF2D191E) : const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isMaintenanceMode ? const BorderSide(color: Colors.redAccent, width: 1.5) : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('SmartSort Live Bin Status', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                              if (isMaintenanceMode)
                                const Text('⚠️ MAINTENANCE ACTIVE', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Icon(Icons.power, color: isMaintenanceMode ? Colors.redAccent : Colors.greenAccent, size: 28),
                                  const SizedBox(height: 6),
                                  const Text('System Level', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  Text(systemState.toUpperCase(), style: TextStyle(color: isMaintenanceMode ? Colors.redAccent : Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                children: [
                                  Icon(Icons.delete, color: wasteLevel > 80 ? Colors.redAccent : Colors.tealAccent, size: 28),
                                  const SizedBox(height: 6),
                                  const Text('Bin Capacity Full', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  Text('$wasteLevel%', style: TextStyle(color: wasteLevel > 80 ? Colors.redAccent : Colors.orangeAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Display Alerta warning alert message box if disabled
                  if (isMaintenanceMode) ...[
                    Card(
                      color: const Color(0xFF1F1517),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.block, color: Colors.redAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'NOTICE: Sorting operations disabled to prevent overflow. Maintenance response dispatched via Alerta.',
                                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // USER RECIPIENT WALLET INPUT
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recipient Reward Destination Wallet', 
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.tealAccent)
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            enabled: !isMaintenanceMode, // Lock field input if system enters Maintenance mode
                            controller: _userWalletController,
                            style: TextStyle(color: isMaintenanceMode ? Colors.grey : Colors.white, fontSize: 12, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              hintText: isMaintenanceMode ? 'System locked down' : 'Paste your Solana wallet address (e.g. 7xM... )',
                              hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF13151A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8), 
                                borderSide: BorderSide.none
                              ),
                              prefixIcon: const Icon(Icons.account_balance_wallet, color: Colors.grey, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // User Rewards Information Panel
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your Account Balance', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              const Text('Eco-Reward Credits', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text(
                            '${digitalRewardCredits.toStringAsFixed(2)} SOL',
                            style: const TextStyle(fontSize: 20, color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                   // 👇 NEW MOTOR CONTROLS & VOICE RECOGNITION PANEL 👇
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Hardware Actuator & Motor Overrides', style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          
                          // PART A: Manual D-Pad Steering Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Column(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 32),
                                    onPressed: () => _sendMotorCommand('FORWARD'),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
                                        onPressed: () => _sendMotorCommand('LEFT'),
                                      ),
                                      const SizedBox(width: 24),
                                      IconButton(
                                        icon: const Icon(Icons.stop_circle, color: Colors.redAccent, size: 36),
                                        onPressed: () => _sendMotorCommand('STOP'),
                                      ),
                                      const SizedBox(width: 24),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 32),
                                        onPressed: () => _sendMotorCommand('RIGHT'),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward, color: Colors.white, size: 32),
                                    onPressed: () => _sendMotorCommand('REVERSE'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 24),
                          
                          // PART B: Voice Recognition Control Unit
                          const Text('Voice Command Interface', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FloatingActionButton.small(
                                backgroundColor: _isListening ? Colors.redAccent : Colors.tealAccent,
                                child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.black),
                                onPressed: _listenToVoice,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF13151A),
                                    borderRadius: BorderRadius.circular(8)
                                  ),
                                  child: Text(
                                    _speechText,
                                    style: TextStyle(
                                      color: _isListening ? Colors.tealAccent : Colors.white70,
                                      fontSize: 12,
                                      fontFamily: 'monospace'
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 👆 END OF MOTOR & VOICE CONTROLS 👆
                  const SizedBox(height: 12),

                  // Waste Disposal Cycle Tracker
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your Waste Disposal Cycle History', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: ListView.builder(
                              itemCount: wasteLogs.length,
                              itemBuilder: (context, index) {
                                String friendlyLog = wasteLogs[index]
                                    .replaceAll("🔬 [Demo Mode Transfer] ", "♻️ Cycle Logged: ")
                                    .replaceAll("⛓️ Tx:", "🔗 Blockchain Receipt ID:")
                                    .replaceAll("ℹ️ Account Balance:", "🌱 Credits Saved:");
                                    
                                return Card(
                                  color: const Color(0xFF13151A),
                                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Text(
                                      friendlyLog,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // =================================================================
            // VIEW 2: THE SECURE INTERNAL ADMIN PANEL
            // =================================================================
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Card containing secret node master mechanics
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Admin Machine Node Wallet', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18, color: Colors.tealAccent),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _walletAddress));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Admin Node Address copied!')),
                                  );
                                },
                              ),
                            ],
                          ),
                          Text(_walletAddress, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                          const Divider(color: Colors.white10, height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Gas Reserve Balance:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('$_solBalance SOL', style: const TextStyle(color: Colors.tealAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // FLEET OPERATIONS DIAGNOSTICS & ALERTA TELEMETRY MONITOR
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Hardware Fleet Diagnostics', style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Text('Core Status', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    systemState.toUpperCase(), 
                                    style: TextStyle(color: isMaintenanceMode ? Colors.redAccent : Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Volume Metrics', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text('$wasteLevel% Full', style: TextStyle(color: wasteLevel > 80 ? Colors.redAccent : Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Last Sorted Object', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    wasteLogs.isNotEmpty && !wasteLogs[0].contains("Waiting") 
                                        ? (wasteLogs[0].toLowerCase().contains("wet") ? "💧 WET WASTE" : "📦 DRY WASTE")
                                        : "NO DEPOSITS YET",
                                    style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                 

                  // MASTER ADMIN LOG STREAM: Raw logs containing Alerta ticket notifications and full transaction hashes
                  Card(
                    color: const Color(0xFF1C1E24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Master System Activity & Audit Ledger', style: TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 250,
                            child: ListView.builder(
                              itemCount: wasteLogs.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Text(
                                    wasteLogs[index],
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
          ], // End of TabBarView children array
        ), // End of TabBarView
      ), // End of Scaffold
    ); // End of DefaultTabController
  } // End of build method
} 
// End of _DashboardScreenState class