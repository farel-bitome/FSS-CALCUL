import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FssCalculApp());

class AppCompany {
  String nom, adresse, telephone, email, identifiantFiscal, registreCommerce, siteWeb, piedTicket;
  AppCompany({
    this.nom = '', this.adresse = '', this.telephone = '', this.email = '',
    this.identifiantFiscal = '', this.registreCommerce = '', this.siteWeb = '',
    this.piedTicket = 'Merci pour votre confiance',
  });
  Map<String,dynamic> toJson() => {
    'nom':nom,'adresse':adresse,'telephone':telephone,'email':email,
    'identifiantFiscal':identifiantFiscal,'registreCommerce':registreCommerce,
    'siteWeb':siteWeb,'piedTicket':piedTicket,
  };
  factory AppCompany.fromJson(Map<String,dynamic> j) => AppCompany(
    nom:j['nom']??'', adresse:j['adresse']??'', telephone:j['telephone']??'',
    email:j['email']??'', identifiantFiscal:j['identifiantFiscal']??'',
    registreCommerce:j['registreCommerce']??'', siteWeb:j['siteWeb']??'',
    piedTicket:j['piedTicket']??'Merci pour votre confiance',
  );
}

class AppUser {
  final String id;
  String nom, identifiant, motDePasse, role;
  bool actif;
  Set<String> permissions;
  AppUser({required this.id,required this.nom,required this.identifiant,required this.motDePasse,
    required this.role,this.actif=true,Set<String>? permissions}) : permissions=permissions??{};
  Map<String,dynamic> toJson()=>{'id':id,'nom':nom,'identifiant':identifiant,'motDePasse':motDePasse,
    'role':role,'actif':actif,'permissions':permissions.toList()};
  factory AppUser.fromJson(Map<String,dynamic> j)=>AppUser(
    id:j['id']??DateTime.now().microsecondsSinceEpoch.toString(),nom:j['nom']??'',
    identifiant:j['identifiant']??'',motDePasse:j['motDePasse']??'',
    role:j['role']??'Utilisateur',actif:j['actif']??true,
    permissions:Set<String>.from(j['permissions']??const []));
}

class Article {
  Article(this.designation,this.prix,this.quantite);
  String designation; double prix; int quantite;
  double get sousTotal=>prix*quantite;
}
class Ticket {
  Ticket(this.numero,this.date,this.articles,this.total);
  final int numero; final DateTime date; final List<Article> articles; final double total;
  Map<String,dynamic> toJson()=>{'numero':numero,'date':date.toIso8601String(),'total':total,
    'articles':articles.map((a)=>{'designation':a.designation,'prix':a.prix,'quantite':a.quantite}).toList()};
  factory Ticket.fromJson(Map<String,dynamic> j)=>Ticket(
    (j['numero'] as num).toInt(),DateTime.tryParse(j['date']??'')??DateTime.now(),
    (j['articles'] as List? ?? const []).map((e)=>Article(e['designation']??'',
      (e['prix'] as num?)?.toDouble()??0.0,(e['quantite'] as num?)?.toInt()??1)).toList(),
    (j['total'] as num?)?.toDouble()??0.0);
}

/// Devises : on mémorise le code ISO, on affiche le symbole.
const devisesDisponibles={'XAF':'FCFA','XOF':'FCFA','EUR':'€','USD':'\$','GBP':'£','CHF':'CHF','MAD':'MAD'};
const libellesDevises={'XAF':'XAF – Franc CFA (CEMAC)','XOF':'XOF – Franc CFA (UEMOA)','EUR':'EUR – Euro',
  'USD':'USD – Dollar américain','GBP':'GBP – Livre sterling','CHF':'CHF – Franc suisse','MAD':'MAD – Dirham marocain'};
String symboleDevise(String code)=>devisesDisponibles[code]??code;

class PrinterService {
  static const _channel=MethodChannel('fss_calcul/printer');
  static Future<String> deviceInfo() async =>
      await _channel.invokeMethod<String>('deviceInfo')??'Android';

  /// [devise] = symbole affiché (ex. FCFA).
  static Future<String> printTicket(Ticket ticket,String devise,AppCompany company) async {
    // SUNMI, Senraise H10 et secours Android sont gérés côté natif (MainActivity.kt)
    return await _channel.invokeMethod<String>('printTicket',{
      'ticket':ticket.numero,'date':_date(ticket.date),'devise':devise,'total':ticket.total,
      'articles':ticket.articles.map((a)=>{'designation':a.designation,'quantite':a.quantite,
        'prix':a.prix,'sousTotal':a.sousTotal}).toList(),
      'societe':company.toJson(),
    })??'Impression demandée';
  }
  static String _fmt(double n){
    final s=n.toStringAsFixed(0); final b=StringBuffer();
    for(int i=0;i<s.length;i++){ if(i>0&&(s.length-i)%3==0&&s[i-1]!='-')b.write(' '); b.write(s[i]); }
    return b.toString();
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
}

class FssCalculApp extends StatelessWidget {
  const FssCalculApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'FSS-CALCUL',
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF0037D6)),
      scaffoldBackgroundColor:Colors.white,useMaterial3:true),
    home:const CaissePage());
}

class CaissePage extends StatefulWidget {
  const CaissePage({super.key});
  @override State<CaissePage> createState()=>_CaissePageState();
}
class _CaissePageState extends State<CaissePage> {
  final designation=TextEditingController(), prix=TextEditingController(), quantite=TextEditingController(text:'1');
  final articles=<Article>[], tickets=<Ticket>[];
  final roles=['Administrateur','Gérant','Caissier','Vendeur','Utilisateur'];
  final permissions=[
    'Vendre','Modifier les ventes','Supprimer les articles','Valider les tickets','Imprimer',
    'Voir l’historique','Réimprimer','Voir la caisse','Clôturer la caisse','Voir les statistiques',
    'Gérer les utilisateurs','Modifier les paramètres'];
  List<AppUser> utilisateurs=[];
  AppCompany societe=AppCompany();
  String devise='XAF'; int page=0, numeroTicket=1;
  String get symbole=>symboleDevise(devise);
  double get total=>articles.fold(0,(s,a)=>s+a.sousTotal);

  @override void initState(){super.initState(); _load();}
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    final d=p.getString('devise')??'XAF';
    devise=devisesDisponibles.containsKey(d)?d:'XAF'; // ancien réglage « FCFA » -> XAF
    numeroTicket=p.getInt('numeroTicket')??1;
    final ts=p.getString('tickets');
    if(ts!=null){try{tickets..clear()..addAll((jsonDecode(ts) as List).map((e)=>Ticket.fromJson(Map<String,dynamic>.from(e))));}catch(_){}}
    final cs=p.getString('societe'); if(cs!=null){try{societe=AppCompany.fromJson(jsonDecode(cs));}catch(_){}} 
    final us=p.getString('utilisateurs');
    if(us!=null){try{utilisateurs=(jsonDecode(us) as List).map((e)=>AppUser.fromJson(Map<String,dynamic>.from(e))).toList();}catch(_){}} 
    if(utilisateurs.isEmpty){
      utilisateurs=[AppUser(id:'admin',nom:'Administrateur',identifiant:'admin',motDePasse:'admin',
        role:'Administrateur',permissions:permissions.toSet())];
      await _saveUsers();
    }
    if(mounted)setState((){});
  }
  Future<void> _saveUsers() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('utilisateurs',jsonEncode(utilisateurs.map((u)=>u.toJson()).toList()));
  }
  Future<void> _saveTickets() async {
    final p=await SharedPreferences.getInstance();
    await p.setInt('numeroTicket',numeroTicket);
    await p.setString('tickets',jsonEncode(tickets.take(500).map((t)=>t.toJson()).toList()));
  }
  Future<void> _saveCompany() async {
    final p=await SharedPreferences.getInstance(); await p.setString('societe',jsonEncode(societe.toJson()));
  }
  Future<void> _saveCurrency(String d) async {
    final p=await SharedPreferences.getInstance(); await p.setString('devise',d);
    if(mounted)setState(()=>devise=d);
  }
  String money(double n)=>'${PrinterService._fmt(n)} $symbole';

  void ajouter(){
    final d=designation.text.trim(), p=double.tryParse(prix.text.replaceAll(',','.')), q=int.tryParse(quantite.text);
    if(d.isEmpty||p==null||p<0||q==null||q<=0){ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('Vérifiez la désignation, le prix et la quantité.')));return;}
    setState(()=>articles.add(Article(d,p,q))); designation.clear(); prix.clear(); quantite.text='1';
  }
  Future<void> enregistrerEtImprimer() async {
    if(articles.isEmpty)return;
    final t=Ticket(numeroTicket++,DateTime.now(),articles.map((a)=>Article(a.designation,a.prix,a.quantite)).toList(),total);
    setState((){tickets.insert(0,t);articles.clear();});
    await _saveTickets();
    try{final r=await PrinterService.printTicket(t,symbole,societe);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(r)));}
    on PlatformException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message??e.code)));}
  }

  Widget accueil()=>Column(children:[
    Container(width:double.infinity,padding:const EdgeInsets.all(10),
      child:Row(children:[Image.asset('assets/fss_logo.png',width:42,height:42),const SizedBox(width:10),
        Expanded(child:Text(societe.nom.isEmpty?'FSS-CALCUL':societe.nom,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)))])),
    Card(margin:const EdgeInsets.all(12),child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      TextField(controller:designation,decoration:const InputDecoration(labelText:'Désignation',prefixIcon:Icon(Icons.shopping_bag))),
      TextField(controller:prix,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:'Prix de vente ($symbole)',prefixIcon:const Icon(Icons.payments))),
      TextField(controller:quantite,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Quantité',prefixIcon:Icon(Icons.numbers))),
      const SizedBox(height:10),SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:ajouter,icon:const Icon(Icons.add),label:const Text('Ajouter l’article')))]))),
    Expanded(child:articles.isEmpty?const Center(child:Text('Aucun article dans le ticket.')):ListView.builder(
      itemCount:articles.length,itemBuilder:(_,i){final a=articles[i];return ListTile(
        title:Text(a.designation,style:const TextStyle(fontWeight:FontWeight.bold)),
        subtitle:Text('${a.quantite} × ${money(a.prix)}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          Text(money(a.sousTotal)),IconButton(onPressed:()=>setState(()=>articles.removeAt(i)),
            icon:const Icon(Icons.delete,color:Color(0xFFD90429))) ]));})),
    Container(padding:const EdgeInsets.fromLTRB(16,10,16,18),color:const Color(0xFF0037D6),child:Row(children:[
      const Text('TOTAL',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.bold)),const Spacer(),
      Text(money(total),style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(width:10),
      FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFFE30613)),
        onPressed:articles.isEmpty?null:enregistrerEtImprimer,icon:const Icon(Icons.print),label:const Text('Valider + imprimer'))]))
  ]);

  Widget historique()=>ListView.builder(padding:const EdgeInsets.all(12),itemCount:tickets.length,itemBuilder:(_,i){
    final t=tickets[i];return Card(child:ListTile(title:Text('Ticket #${t.numero}'),
      subtitle:Text('${t.articles.length} article(s) • ${money(t.total)}'),
      trailing:IconButton(icon:const Icon(Icons.print),onPressed:()async{
        try{final r=await PrinterService.printTicket(t,symbole,societe);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(r)));}
        on PlatformException catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message??e.code)));}})));});

  Future<void> _companyDialog() async {
    final fields=[
      ['Nom de la société',societe.nom],['Adresse',societe.adresse],['Téléphone',societe.telephone],
      ['E-mail',societe.email],['Identifiant fiscal / NIF',societe.identifiantFiscal],
      ['Registre de commerce / RCCM',societe.registreCommerce],['Site web',societe.siteWeb],
      ['Pied de ticket',societe.piedTicket]];
    final c=fields.map((e)=>TextEditingController(text:e[1])).toList();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Paramètres société'),
      content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,
        children:[for(int i=0;i<fields.length;i++)TextField(controller:c[i],
          decoration:InputDecoration(labelText:fields[i][0],prefixIcon:Icon(_companyIcon(i))),
          maxLines:i==1?2:1)]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),
        FilledButton(onPressed:()async{
          societe=AppCompany(nom:c[0].text.trim(),adresse:c[1].text.trim(),telephone:c[2].text.trim(),
            email:c[3].text.trim(),identifiantFiscal:c[4].text.trim(),registreCommerce:c[5].text.trim(),
            siteWeb:c[6].text.trim(),piedTicket:c[7].text.trim().isEmpty?'Merci pour votre confiance':c[7].text.trim());
          await _saveCompany();if(mounted){setState((){});Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Informations société enregistrées.')));}},
          child:const Text('Enregistrer'))]));
  }
  IconData _companyIcon(int i)=>[Icons.business,Icons.location_on,Icons.phone,Icons.email,Icons.badge,Icons.receipt_long,Icons.language,Icons.message][i];

  Future<void> _userDialog({AppUser? u}) async {
    final n=TextEditingController(text:u?.nom??''), id=TextEditingController(text:u?.identifiant??''), pw=TextEditingController(text:u?.motDePasse??'');
    String role=u?.role??roles[1]; bool actif=u?.actif??true; Set<String> perms={...(u?.permissions??{'Vendre','Imprimer'})};
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(u==null?'Créer un utilisateur':'Modifier l’utilisateur'),
      content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:n,decoration:const InputDecoration(labelText:'Nom complet')),
        TextField(controller:id,decoration:const InputDecoration(labelText:'Identifiant')),
        TextField(controller:pw,obscureText:true,decoration:const InputDecoration(labelText:'Mot de passe')),
        DropdownButtonFormField<String>(initialValue:role,decoration:const InputDecoration(labelText:'Rôle'),
          items:roles.map((r)=>DropdownMenuItem(value:r,child:Text(r))).toList(),onChanged:(v)=>setD(()=>role=v??role)),
        SwitchListTile(title:const Text('Utilisateur actif'),value:actif,onChanged:(v)=>setD(()=>actif=v)),
        const Align(alignment:Alignment.centerLeft,child:Text('Droits / permissions',style:TextStyle(fontWeight:FontWeight.bold))),
        ...permissions.map((p)=>CheckboxListTile(dense:true,title:Text(p),value:perms.contains(p),
          onChanged:(v)=>setD(()=>v==true?perms.add(p):perms.remove(p))))
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),FilledButton(onPressed:()async{
        if(n.text.trim().isEmpty||id.text.trim().isEmpty)return;
        if(u==null)utilisateurs.add(AppUser(id:DateTime.now().microsecondsSinceEpoch.toString(),nom:n.text.trim(),
          identifiant:id.text.trim(),motDePasse:pw.text,role:role,actif:actif,permissions:perms));
        else{u.nom=n.text.trim();u.identifiant=id.text.trim();if(pw.text.isNotEmpty)u.motDePasse=pw.text;u.role=role;u.actif=actif;u.permissions=perms;}
        await _saveUsers();if(mounted){setState((){});Navigator.pop(ctx);}},
        child:const Text('Enregistrer'))])));
  }

  Widget utilisateursPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    Row(children:[const Expanded(child:Text('UTILISATEURS',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
      FilledButton.icon(onPressed:()=>_userDialog(),icon:const Icon(Icons.person_add),label:const Text('Créer'))]),
    const SizedBox(height:8),const Text('Définissez les rôles et droits selon votre organisation.'),
    const SizedBox(height:12),...utilisateurs.map((u)=>Card(child:ListTile(
      leading:CircleAvatar(child:Icon(u.actif?Icons.person:Icons.person_off)),title:Text(u.nom),
      subtitle:Text('${u.identifiant} • ${u.role}\n${u.permissions.length} droit(s)'),
      isThreeLine:true,trailing:Wrap(children:[
        IconButton(onPressed:()=>_userDialog(u:u),icon:const Icon(Icons.edit)),
        IconButton(onPressed:()async{if(utilisateurs.length>1){setState(()=>utilisateurs.remove(u));await _saveUsers();}},
          icon:const Icon(Icons.delete))]))))
  ]);

  Widget parametres()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('PARAMÈTRES',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    const SizedBox(height:12),
    Card(child:ListTile(leading:Image.asset('assets/fss_logo.png',width:48,height:48),
      title:Text(societe.nom.isEmpty?'Paramètres société':societe.nom),
      subtitle:Text(societe.nom.isEmpty?'Renseigner les informations de votre société':'Modifier les informations de la société'),
      trailing:const Icon(Icons.chevron_right),onTap:_companyDialog)),
    Card(child:ListTile(leading:const Icon(Icons.currency_exchange),title:const Text('Devise'),
      subtitle:Text(libellesDevises[devise]??devise),trailing:DropdownButton<String>(value:devise,
        items:devisesDisponibles.keys.map((d)=>DropdownMenuItem(value:d,child:Text(d))).toList(),
        onChanged:(v){if(v!=null)_saveCurrency(v);}))),
    const Divider(height:28),
    const Text('IMPRESSION MULTI-TERMINAUX',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    FutureBuilder<String>(future:PrinterService.deviceInfo(),builder:(_,snap)=>ListTile(
      leading:const Icon(Icons.print),title:const Text('Terminal détecté'),subtitle:Text(snap.data??'Détection…'))),
    const ListTile(leading:Icon(Icons.memory),title:Text('Imprimante intégrée Android / constructeur')),
    const ListTile(leading:Icon(Icons.usb),title:Text('USB / ESC-POS')),
    const ListTile(leading:Icon(Icons.bluetooth),title:Text('Bluetooth / ESC-POS')),
    const ListTile(leading:Icon(Icons.wifi),title:Text('Wi-Fi / réseau')),
    const ListTile(leading:Icon(Icons.print_outlined),title:Text('Service d’impression Android')),
    const SizedBox(height:8),
    const Text('Les informations société sont mémorisées sur le terminal et reprises sur les tickets.')
  ]);

  @override Widget build(BuildContext context){
    final pages=[accueil(),historique(),parametres(),utilisateursPage()];
    return Scaffold(
      appBar:AppBar(backgroundColor:const Color(0xFF0037D6),foregroundColor:Colors.white,
        title:Row(children:[Image.asset('assets/fss_logo.png',width:32,height:32),const SizedBox(width:8),const Text('FSS-CALCUL')]),
      ),
      body:pages[page],
      bottomNavigationBar:NavigationBar(selectedIndex:page,onDestinationSelected:(i)=>setState(()=>page=i),
        destinations:const[
          NavigationDestination(icon:Icon(Icons.point_of_sale),label:'Accueil'),
          NavigationDestination(icon:Icon(Icons.history),label:'Historique'),
          NavigationDestination(icon:Icon(Icons.settings),label:'Paramètres'),
          NavigationDestination(icon:Icon(Icons.people),label:'Utilisateurs'),
        ])
    );
  }
  @override void dispose(){designation.dispose();prix.dispose();quantite.dispose();super.dispose();}
}
