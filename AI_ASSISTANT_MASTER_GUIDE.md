# 🤖 AI Assistant Master Guide - StepheyBot Music System

**Version**: 2.0  
**Last Updated**: June 27, 2025  
**Migration Status**: qBittorrent → Transmission (COMPLETED)

---

## 🎯 **Purpose of This Document**

This guide provides comprehensive knowledge for AI assistants working on the StepheyBot Music system. It contains everything needed to understand, troubleshoot, and extend the system without having to reverse-engineer from scratch.

---

## 🏗️ **System Architecture Overview**

### **Core Philosophy**
StepheyBot Music is a private, self-hosted Spotify-like system with automated music discovery and downloading capabilities. It combines multiple services to create a seamless experience:

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   User Interface    │◄──►│  StepheyBot Music   │◄──►│     External APIs   │
│  (Frontend/WebUI)   │    │      Brain          │    │  (MusicBrainz, etc) │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
           │                           │                           │
           ▼                           ▼                           ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│     Navidrome       │    │      Lidarr         │    │     Jackett         │
│  (Music Streaming)  │    │  (Music Manager)    │    │   (Torrent Search)  │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
           │                           │                           │
           ▼                           ▼                           ▼
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│  Music Library      │    │    Transmission     │    │    Gluetun VPN      │
│ (/mnt/hdd/music/)   │    │   (Torrent Client)  │    │   (Network Proxy)   │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

### **Data Flow: Search → Download → Import**
1. **User searches** for music via StepheyBot Music Brain frontend
2. **System searches** both local library (Navidrome) AND external sources (via Jackett)
3. **Local results** show for immediate streaming
4. **External results** show with download buttons for music not in library
5. **Download request** includes magnet link from search results
6. **StepheyBot Music Brain** adds torrent to Transmission (via VPN)
7. **Transmission** downloads files to `/downloads` directory
8. **Lidarr** monitors and imports completed downloads to music library
9. **Navidrome** detects new music and makes it available for streaming

---

## 🔧 **Service Details**

### **StepheyBot Music Brain** (Rust/Axum)
- **Role**: Central coordinator and API hub
- **Port**: 8083
- **Key Features**:
  - Music recommendation engine
  - Global search (local + external)
  - Download queue management
  - Transmission integration
  - Lidarr integration
  - Frontend serving

**Critical Environment Variables**:
```yaml
STEPHEYBOT__TRANSMISSION__URL=http://stepheybot_music_vpn:9091
STEPHEYBOT__TRANSMISSION__USERNAME=admin
STEPHEYBOT__TRANSMISSION__PASSWORD=adminadmin
STEPHEYBOT__LIDARR__URL=http://lidarr:8686
STEPHEYBOT__LIDARR__API_KEY=${STEPHEYBOT__LIDARR__API_KEY}
```

### **Transmission** (Torrent Client)
- **Role**: Download torrents via VPN
- **Access**: http://localhost:9092 (external) / stepheybot_music_vpn:9091 (internal)
- **Credentials**: admin/adminadmin
- **Critical**: Routes through Gluetun VPN for privacy

**Volume Mappings** (CRITICAL):
```yaml
- /mnt/nvme/upload:/downloads
- /mnt/nvme/upload:/hot_downloads  # IMPORTANT: Both paths needed!
- /mnt/nvme/upload:/watch
```

### **Lidarr** (Music Management)
- **Role**: Automated music library management
- **Port**: 8686
- **Integration**: Uses Transmission as download client
- **API Key**: Extract from `/config/config.xml` in container

### **Navidrome** (Music Streaming)
- **Role**: Subsonic-compatible music server
- **Port**: 4533 (internal)
- **Library Path**: `/mnt/hdd/media/music/library`

### **Jackett** (Torrent Indexer)
- **Role**: Aggregates torrent sites for music search
- **Port**: 9117
- **Integration**: Provides torrent feeds to Lidarr

### **Gluetun** (VPN)
- **Role**: Secure VPN tunnel for torrent traffic
- **Provider**: Mullvad WireGuard
- **Critical**: All torrent traffic routes through this

---

## 🚨 **Common Issues & Solutions**

### **Issue 1: Downloads Show "queued_without_monitoring"**
**Symptoms**: Download requests return `"status": "queued_without_monitoring"` with `"search timeout"`

**Root Cause**: Frontend not passing magnet links in download requests

**Solution**: Ensure frontend passes `magnet_url` as `external_id`:
```javascript
// ❌ Wrong (causes timeout)
external_id: track.id

// ✅ Correct (works)
external_id: track.magnet_url || track.external_id || track.id
```

### **Issue 2: Transmission Permission Errors**
**Symptoms**: 
```
Error: Couldn't move /downloads/incomplete to /hot_downloads: Permission Denied
```

**Root Cause**: Missing volume mapping for `/hot_downloads`

**Solution**: Ensure both volume mappings exist:
```yaml
volumes:
    - /mnt/nvme/upload:/downloads
    - /mnt/nvme/upload:/hot_downloads  # This is often missing!
```

### **Issue 3: qBittorrent Authentication Issues** 
**Status**: MIGRATED TO TRANSMISSION (June 27, 2025)

**Background**: qBittorrent had complex authentication issues that were difficult to resolve consistently.

**Solution**: Complete migration to Transmission completed successfully.

### **Issue 4: Lidarr Can't Find Downloads**
**Symptoms**: Downloads complete but Lidarr doesn't import

**Solutions**:
1. **Check Remote Path Mappings**: Usually should be EMPTY (delete any existing)
2. **Verify Volume Consistency**: Both Lidarr and Transmission must see same `/downloads` path
3. **Test Connection**: Use Lidarr's download client test feature

---

## 🔌 **API Reference**

### **Health & Status**
```bash
GET  /health                           # Service health check
GET  /api/v1/stats                     # System statistics
GET  /api/v1/navidrome/status          # Navidrome integration status
GET  /api/v1/lidarr/status            # Lidarr integration status
```

### **Search & Discovery**
```bash
GET  /api/v1/search/global/:query      # Search local + external sources
GET  /api/v1/search/external/:query    # External sources only (torrents)
GET  /api/v1/discover                  # Music discovery/recommendations
```

### **Download Management**
```bash
POST /api/v1/download/request          # Request download (NEEDS magnet_url!)
GET  /api/v1/download/stats            # Download statistics
GET  /api/v1/download/active           # Active downloads
POST /api/v1/download/pause/:hash      # Pause download
POST /api/v1/download/resume/:hash     # Resume download
```

**Critical Download Request Format**:
```json
{
    "title": "Track Title",
    "artist": "Artist Name", 
    "album": "Album Name",
    "external_id": "magnet:?xt=urn:btih:...",  // MUST include magnet link!
    "source": "lidarr"
}
```

---

## 🐳 **Docker Configuration**

### **Network Setup**
All services run on `nextcloud_net` and `proxy` networks. Key containers:
- `stepheybot_music_brain` (StepheyBot Music Brain)
- `stepheybot_music_transmission` (runs through VPN)
- `stepheybot_music_vpn` (Gluetun VPN)
- `stepheybot_music_lidarr`
- `stepheybot_music_navidrome`

### **Volume Mappings**
```yaml
# StepheyBot Music Brain
- /mnt/hdd/media/music/library:/music:ro
- /mnt/nvme/upload:/hot_downloads
- /mnt/nvme/upload:/processing

# Transmission (CRITICAL - both mappings needed)
- /mnt/nvme/upload:/downloads
- /mnt/nvme/upload:/hot_downloads

# Lidarr
- /mnt/hdd/media/music/library:/music:ro
- /mnt/nvme/upload:/downloads

# Navidrome
- /mnt/hdd/media/music/library:/music:ro
```

### **Service Dependencies**
```
Transmission → Gluetun (VPN)
StepheyBot Music Brain → Transmission, Lidarr, Navidrome
Lidarr → Transmission
```

---

## 🧪 **Testing & Verification**

### **Quick Health Check**
```bash
# 1. Verify all services running
docker ps | grep -E "(transmission|lidarr|navidrome|stepheybot_music)"

# 2. Test API endpoints
curl http://localhost:8083/health
curl http://localhost:8083/api/v1/download/stats

# 3. Test Transmission connection
curl -s http://localhost:8083/api/v1/download/active | jq .
```

### **End-to-End Download Test**
```bash
# Test with known working magnet link
curl -X POST "http://localhost:8083/api/v1/download/request" \
     -H "Content-Type: application/json" \
     -d '{
       "title": "Test Download",
       "artist": "Test Artist",
       "album": "Test Album", 
       "external_id": "magnet:?xt=urn:btih:...",
       "source": "test"
     }'

# Should return: "status": "queued" (not "queued_without_monitoring")
```

### **Frontend Test**
1. Navigate to `http://localhost:8083/search`
2. Search for music not in library
3. Click download button on external result
4. Verify download appears in `http://localhost:8083/downloads`

---

## 🛠️ **Troubleshooting Workflow**

### **Step 1: Service Health**
```bash
# Check all containers
docker ps | grep stepheybot_music
docker logs stepheybot_music_brain --tail 20
docker logs stepheybot_music_transmission --tail 20
```

### **Step 2: Network Connectivity**
```bash
# Test internal service communication
docker exec stepheybot_music_brain timeout 5 bash -c "</dev/tcp/stepheybot_music_vpn/9091"
```

### **Step 3: API Functionality**
```bash
# Test key endpoints
curl http://localhost:8083/health
curl http://localhost:8083/api/v1/lidarr/status
curl http://localhost:8083/api/v1/download/stats
```

### **Step 4: Download Pipeline**
```bash
# Test search
curl "http://localhost:8083/api/v1/search/global/test%20query"

# Test download (with magnet link)
curl -X POST "http://localhost:8083/api/v1/download/request" [...]
```

---

## 📋 **Known Working Configurations**

### **Lidarr Download Client Settings**
```yaml
Name: Transmission Music
Host: stepheybot_music_vpn
Port: 9091
URL Base: /transmission/
Username: admin
Password: adminadmin
Category: [EMPTY]
Post-Import Category: music-imported
Directory: [EMPTY]
Remote Path Mappings: [DELETE ALL - should be empty]
```

### **Transmission WebUI Settings**
- **Download Directory**: `/downloads`
- **Incomplete Directory**: `/downloads/incomplete` ✅ ENABLED
- **Watch Directory**: `/watch` ✅ ENABLED  
- **Seeding Ratio**: 2.0
- **Seeding Time**: 30 minutes

### **Environment Variables (docker-compose.yml)**
```yaml
# StepheyBot Music Brain
- STEPHEYBOT__TRANSMISSION__URL=http://stepheybot_music_vpn:9091
- STEPHEYBOT__TRANSMISSION__USERNAME=admin
- STEPHEYBOT__TRANSMISSION__PASSWORD=adminadmin
- STEPHEYBOT__LIDARR__URL=http://lidarr:8686
- STEPHEYBOT__LIDARR__API_KEY=${STEPHEYBOT__LIDARR__API_KEY}

# Transmission
- USER=admin
- PASS=adminadmin
- PUID=1000
- PGID=1000
```

---

## 🔄 **Recent Changes & Migrations**

### **qBittorrent → Transmission Migration (June 27, 2025)**
**Reason**: qBittorrent authentication consistently problematic  
**Solution**: Complete migration to Transmission with RPC API  
**Status**: ✅ COMPLETED - System fully operational

**Key Changes**:
1. Replaced `QBittorrentClient` with `TransmissionClient`
2. Updated RPC communication with session management
3. Modified volume mappings for proper directory access
4. Updated frontend to pass magnet links correctly

### **Frontend Download Fix (June 27, 2025)**
**Issue**: Download buttons not passing magnet links  
**Fix**: Updated `GlobalSearch.svelte` to use `track.magnet_url || track.external_id || track.id`  
**Status**: ✅ COMPLETED

---

## 🎨 **User Interface Notes**

### **Neon Theme**
- User prefers neon aesthetic: pinks, blues, purples
- Cyberpunk/techno vibe throughout interface
- Search interface has smooth animations
- Real-time download progress bars

### **Key UI Components**
- **Search Page**: `/search` - Global search with download buttons
- **Downloads Page**: `/downloads` - Real-time download monitoring  
- **Discovery Page**: `/discover` - Music recommendations
- **Streaming**: Via Navidrome integration

---

## 🚀 **Performance Characteristics**

### **Known Good Performance**
- **API Response Times**: Sub-second for most endpoints
- **Search Response**: ~2 seconds for global search
- **Download Request**: <1 second to queue
- **Concurrent Downloads**: Supports 5 simultaneous
- **Auto-refresh**: Downloads page updates every 3 seconds

### **Storage Architecture**
```
Hot Storage (NVMe): /mnt/nvme/upload/
├── downloads/          # Active downloads
├── incomplete/         # In-progress downloads  
├── complete/          # Completed downloads
├── processing/        # Being processed by Lidarr
└── watch/            # Watch folder for .torrent files

Cold Storage (HDD): /mnt/hdd/media/music/library/
└── Final music library for streaming
```

---

## 🔐 **Security & Access**

### **Default Credentials**
- **Transmission**: admin/adminadmin
- **Lidarr**: No auth (internal only)
- **Navidrome**: Set during initial setup
- **OAuth2 Proxy**: Configured for external access

### **Network Security**
- All torrent traffic routes through Mullvad VPN
- Internal services communicate via Docker networks
- External access protected by OAuth2 proxy where needed

---

## 📞 **Support & Debugging**

### **Log Locations**
```bash
# Service logs
docker logs stepheybot_music_brain
docker logs stepheybot_music_transmission  
docker logs stepheybot_music_lidarr
docker logs stepheybot_music_vpn

# With follow
docker logs stepheybot_music_brain -f
```

### **Configuration Files**
```bash
# Transmission config
docker exec stepheybot_music_transmission cat /config/settings.json

# Lidarr API key
docker exec stepheybot_music_lidarr cat /config/config.xml | grep ApiKey
```

### **Quick Fixes**
```bash
# Restart entire music stack
docker-compose restart stepheybot-music transmission lidarr

# Reset Transmission (if needed)
docker-compose stop transmission
docker-compose rm -f transmission  
docker-compose up -d transmission

# Check disk space
df -h /mnt/nvme/upload
df -h /mnt/hdd/media
```

---

## 🎯 **System Goals & Philosophy**

### **Core Objectives**
1. **Private Spotify Alternative**: Complete control over music library
2. **Automated Discovery**: Find and download music not in library
3. **Seamless Integration**: All services work together transparently  
4. **High Performance**: Fast search, streaming, and downloads
5. **User-Friendly**: Simple interface hiding complex automation

### **Technical Principles**
- **Service-Oriented Architecture**: Each component has clear responsibility
- **API-First Design**: All functionality exposed via REST APIs
- **Container-Based**: Easy deployment and management
- **Security-Focused**: VPN for downloads, OAuth2 for access
- **Performance-Optimized**: Tiered storage, efficient caching

---

## 🎵 **Success Metrics**

### **System Health Indicators**
- All containers running and healthy
- API response times <2 seconds
- Search returns both local and external results
- Downloads progress from "queued" to "downloading" to "completed"
- Downloaded music appears in Navidrome library

### **User Experience Goals**
- Single search interface for everything
- One-click downloads for missing music
- Real-time download progress
- Automatic library updates
- Mobile-responsive neon interface

---

**🎉 Current Status: SYSTEM FULLY OPERATIONAL 🎉**

*This documentation should provide sufficient context for any AI assistant to understand, troubleshoot, and extend the StepheyBot Music system effectively.*