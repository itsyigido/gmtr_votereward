# gmtr_votereward

**[gmod.tr](https://gmod.tr) sunucu listesi için oy ödülü eklentisi.** Oyuncular gmod.tr'de sunucunuza oy verir, oyun içinde `/reward` yazar ve ödüllerini alır. Oyun doğrulaması gmod.tr'nin resmî API'si üzerinden sunucu tarafında yapılır, bu yüzden aynı oy iki kez kullanılamaz ve oyuncu sahte oy bildiremez.

Helix ve DarkRP ile kutudan çıktığı gibi çalışır. İkisi de yoksa sandbox tabanlı sunucularda da çalışır.

---

## Özellikler

- **Sunucu taraflı oy doğrulaması:** `POST /votes/{steamid64}/claim` ile oy, gmod.tr tarafında tek seferlik olarak harcanır. Oy verilmemişse, ödül o gün zaten alınmışsa veya istek sınırına takılınmışsa oyuncuya Türkçe açıklama gösterilir.
- **Ağırlıklı rastgele ödül havuzu:** Her oyda havuzdan tek bir ödül çekilir. Şansı `weight / toplam weight` olarak hesaplanır. Düşük ihtimalli nadir ödüller kolayca tanımlanır.
- **Çerçeveye göre ödül tipleri**
  | Tip | Helix | DarkRP | Sandbox |
  |---|:-:|:-:|:-:|
  | `money` (para) | ✔ karakter parası | ✔ `addMoney` | ✖ |
  | `item` (envanter eşyası) | ✔ envanter doluysa yere düşer | ✖ | ✖ |
  | `weapon` (silah) | ✖ (Helix'te silahlar item'dır) | ✔ | ✔ |
  | `shipment` (F4 kolisi) | ✖ | ✔ | ✖ |
  | `command` (konsol komutu) | ✔ | ✔ | ✔ |
  | Özel `Grant` fonksiyonu | ✔ | ✔ | ✔ |
- **Ödül hiçbir zaman kaybolmaz:** Oy harcandıktan sonra ödül teslim edilemezse (oyuncu çıktıysa, karakter seçili değilse ya da eşya verilemediyse) ödül `data/gmtr_votereward/pending.json` dosyasına yazılır. Oyuncu bir sonraki girişinde veya `/reward` yazdığında teslim edilir. Teslim başarısız olursa havuzdaki başka bir ödül denenir.
- **Önce havuz, sonra oy:** Havuzda geçerli bir ödül yoksa API'ye hiç istek atılmaz ve oyuncunun oyu boşa harcanmaz.
- **Tek komutla oy sayfası:** `/oyver` gmod.tr oy sayfasını açar ve linki panoya kopyalar. Steam overlay kapalı olan oyuncular linki tarayıcıya yapıştırabilir. Link config'e yazılmaz, API'den otomatik çekilir.
- **Giriş hatırlatması:** Oyuncu girdikten bir süre sonra, oy vermediyse "oy ver", oy verip ödülünü almadıysa "ödülün bekliyor" mesajı alır (oturum başına bir kez).
- **Güvenlik**
  - API anahtarı yalnızca sunucu dosyasında (`sv_config.lua`) durur ve istemciye gönderilmez.
  - `command` ödüllerinde oyuncu adındaki `;`, tırnak ve kontrol karakterleri temizlenir, böylece konsola komut enjekte edilemez.
  - Oyuncu başına 5 sn bekleme süresi uygulanır, eşzamanlı istekler kilitlenir ve aynı anda gelen sunucu bilgisi istekleri tek HTTP çağrısında birleştirilir.
  - İstemci yalnızca `https://` ile başlayan linkleri açar.
- **Loglama:** Her ödül, bekletme ve API hatası `data/gmtr_votereward/log.txt` dosyasına tarihli olarak yazılır.
- **Yönetici denetimi:** `gmtr_vr_status` komutu (konsol veya superadmin) havuzdaki her ödülün geçerli olup olmadığını listeler, API anahtarını test eder ve sunucunun gmod.tr sırasını, aylık oy sayısını ve oy linkini gösterir.

## Entegrasyon

| Sistem | Nasıl bağlanır |
|---|---|
| **gmod.tr API v1** | `https://gmod.tr/api/v1`, `Bearer gmtr_...` sunucu anahtarı. Kullanılan uçlar: `GET /server`, `GET /votes/{sid64}`, `POST /votes/{sid64}/claim` ([geliştirici belgesi](https://gmod.tr/devs.md)) |
| **Helix** | Komutlar `ix.command` ile kaydedilir (sohbet tamamlama ve komut listesinde görünür). Ödül o anki karaktere verilir. Hatırlatma ve bekleyen ödül teslimi `PlayerLoadedCharacter` ile tetiklenir. |
| **DarkRP** | Komutlar `/` ve `!` önekiyle `PlayerSay` üzerinden çalışır. Para `addMoney` ile verilir. Koliler `CustomShipments` içinde adla bulunup oyuncunun önüne bırakılır. |
| **Sandbox sunucu** | `PlayerSay` ve `PlayerInitialSpawn` kullanılır. `weapon`, `command` ve özel ödüller çalışır. |
| **Diğer eklentiler** | `command` tipiyle (örn. `ulx`/`sam` komutları, `{steamid}` `{steamid64}` `{userid}` `{name}` yer tutucularıyla) veya özel `Grant` fonksiyonuyla herhangi bir sisteme bağlanabilir. |

Çerçeve açılışta otomatik algılanır, ayrıca ayar yapmaya gerek yoktur.

## Kurulum

1. Klasörü `garrysmod/addons/gmtr_votereward` olarak kopyalayın.
2. gmod.tr'de sunucunuzun düzenleme sayfasından (veya profilinizin sağ tarafından) **sunucu anahtarını** alın. Bu anahtar `gmtr_` ile başlar. `gmtd_` ile başlayan kişisel anahtarlar oy uçlarında 403 hatası verir.
3. Anahtarı `lua/gmtr_votereward/sv_config.lua` dosyasına yazın:
   ```lua
   GMTR_VR.ApiKey = "gmtr_..."
   ```
4. `lua/gmtr_votereward/sh_config.lua` içinde ödül havuzunu düzenleyin.
5. Sunucuyu yeniden başlatın ve konsolda `gmtr_vr_status` çalıştırarak kurulumu doğrulayın.

> ⚠️ `sv_config.lua` gizli anahtar içerir. Herkese açık bir depoya göndermeyin, `.gitignore`'a ekleyin.

## Yapılandırma

```lua
-- /reward ve /oyver sabittir, buraya eş anlamlıları eklenir
CFG.Aliases = {
	Reward = {"odul"},
	Vote = {"oyver"},
}

CFG.RemindOnJoin = true   -- girişte oy hatırlatması
CFG.RemindDelay = 20      -- girişten kaç sn sonra

CFG.Rewards = {
	-- Helix
	{type = "money", amount = 100, weight = 70},
	{type = "item", item = "health_potion", amount = 2, weight = 25},

	-- DarkRP
	{type = "weapon", class = "weapon_ak472", weight = 10},
	{type = "shipment", shipment = "AK47", count = 5, weight = 2},

	-- Her yerde
	{type = "command", command = "ulx adduserid {steamid} vip", name = "1 günlük VIP", weight = 1},
	{name = "Sürpriz", weight = 5, Grant = function(client, character)
		client:SetHealth(client:GetMaxHealth())
		return true -- false dönerse teslim başarısız sayılır, başka ödül denenir
	end},
}
```

Her ödülde `name = "..."` ile oyuncuya görünen ad değiştirilebilir. Sunucunun çerçevesine uymayan ödüller (örn. DarkRP'de `item`) çekilişte otomatik olarak atlanır.

## Komutlar

| Komut | Kim | Açıklama |
|---|---|---|
| `/reward` | Herkes | Oyu doğrular ve ödülü verir. Bekleyen ödül varsa önce onu teslim eder. |
| `/oyver` | Herkes | gmod.tr oy sayfasını açar ve linki panoya kopyalar. |
| `gmtr_vr_status` | Konsol / superadmin | Havuz geçerliliği, anahtar testi, sıra ve aylık oy bilgisi |

## Dosya yapısı

```
lua/autorun/gmtr_votereward.lua      yükleyici
lua/gmtr_votereward/sh_config.lua    ödül havuzu ve ayarlar
lua/gmtr_votereward/sh_commands.lua  Helix komutları
lua/gmtr_votereward/sv_config.lua    API anahtarı (gizli)
lua/gmtr_votereward/sv_votereward.lua  API, çekiliş, teslim, bekleyen ödüller
lua/gmtr_votereward/cl_votereward.lua  sohbet mesajı ve oy sayfası
```