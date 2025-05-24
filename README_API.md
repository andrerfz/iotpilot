# 🔌 IoT Pilot API Endpoints

Complete documentation of all API endpoints in the IoT Pilot system.

## 📊 Status Legend

- ✅ **Implemented & Working** - Ready for use
- ⚠️ **Partial Implementation** - Some functionality missing
- ❌ **Not Implemented** - Endpoint missing
- 🔧 **Needs Testing** - Implementation exists but untested

---

## 🏥 Health & Status

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/health` | ✅ | System health check | No |

---

## 🔐 Authentication

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `POST` | `/api/auth/login` | ✅ | User login | No |
| `POST` | `/api/auth/logout` | ✅ | User logout | Yes |
| `POST` | `/api/auth/register` | ⚠️ | User registration (alias to login) | No |
| `GET` | `/api/auth/me` | ✅ | Get current user info | Yes |
| `GET` | `/api/auth/api-keys` | ✅ | List user's API keys | Yes |
| `POST` | `/api/auth/api-keys` | ✅ | Create new API key | Yes |
| `DELETE` | `/api/auth/api-keys` | ✅ | Delete API key | Yes |

### Missing Auth Endpoints
- ❌ `POST /api/auth/forgot-password` - Password reset
- ❌ `POST /api/auth/reset-password` - Password reset confirmation
- ❌ `POST /api/auth/change-password` - Change user password
- ❌ `POST /api/auth/refresh` - Refresh JWT token

---

## 📱 Device Management

### Core Device Operations

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/devices` | ✅ | List all devices | Yes |
| `POST` | `/api/devices` | ✅ | Register new device | API Key |
| `POST` | `/api/devices/register` | ❌ | Device registration alias | API Key |
| `POST` | `/api/devices/tailscale-register` | ✅ | Tailscale device registration | API Key |
| `POST` | `/api/heartbeat` | ✅ | Device heartbeat | API Key |

### Individual Device Operations

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/devices/[id]` | ✅ | Get device details | Yes |
| `PUT` | `/api/devices/[id]` | ✅ | Update device info | Yes |
| `DELETE` | `/api/devices/[id]` | ✅ | Delete device | Yes |

### Device Metrics

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/devices/[id]/metrics` | ✅ | Get device metrics | Yes |
| `POST` | `/api/devices/[id]/metrics` | ❌ | Submit metrics manually | API Key |

### Device Commands

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/devices/[id]/commands` | ✅ | List device commands | Yes |
| `POST` | `/api/devices/[id]/commands` | ✅ | Issue new command | Yes |
| `GET` | `/api/devices/[id]/commands/[commandId]` | ✅ | Get command details | Yes |
| `PUT` | `/api/devices/[id]/commands/[commandId]` | ❌ | Update command status | Yes |
| `DELETE` | `/api/devices/[id]/commands/[commandId]` | ❌ | Cancel command | Yes |

### Missing Device Endpoints
- ❌ `GET /api/devices/[id]/logs` - Get device logs
- ❌ `POST /api/devices/[id]/logs` - Submit device logs
- ❌ `GET /api/devices/[id]/files` - File system browser
- ❌ `POST /api/devices/[id]/files/upload` - File upload
- ❌ `GET /api/devices/[id]/files/download` - File download
- ❌ `GET /api/devices/[id]/terminal` - SSH terminal access
- ❌ `POST /api/devices/[id]/reboot` - Quick reboot
- ❌ `POST /api/devices/[id]/shutdown` - Quick shutdown
- ❌ `GET /api/devices/[id]/network` - Network configuration
- ❌ `PUT /api/devices/[id]/network` - Update network settings

---

## 📊 Monitoring & Metrics

### System Metrics

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/metrics` | ❌ | System-wide metrics | Yes |
| `GET` | `/api/metrics/dashboard` | ❌ | Dashboard metrics | Yes |
| `GET` | `/api/metrics/export` | ❌ | Export metrics data | Yes |

### Alerts

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/alerts` | ❌ | List all alerts | Yes |
| `POST` | `/api/alerts` | ❌ | Create custom alert | Yes |
| `GET` | `/api/alerts/[id]` | ❌ | Get alert details | Yes |
| `PUT` | `/api/alerts/[id]` | ❌ | Update alert | Yes |
| `DELETE` | `/api/alerts/[id]` | ❌ | Delete alert | Yes |
| `POST` | `/api/alerts/[id]/resolve` | ❌ | Mark alert as resolved | Yes |

### Missing Monitoring Endpoints
- ❌ `GET /api/monitoring/status` - Overall system status
- ❌ `GET /api/monitoring/uptime` - System uptime statistics
- ❌ `POST /api/monitoring/test` - Test monitoring connectivity

---

## 🔧 Administration

### User Management

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/admin/users` | ❌ | List all users | Admin |
| `POST` | `/api/admin/users` | ❌ | Create user | Admin |
| `GET` | `/api/admin/users/[id]` | ❌ | Get user details | Admin |
| `PUT` | `/api/admin/users/[id]` | ❌ | Update user | Admin |
| `DELETE` | `/api/admin/users/[id]` | ❌ | Delete user | Admin |
| `PUT` | `/api/admin/users/[id]/role` | ❌ | Change user role | Admin |

### System Configuration

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/admin/config` | ❌ | Get system config | Admin |
| `PUT` | `/api/admin/config` | ❌ | Update system config | Admin |
| `GET` | `/api/admin/logs` | ❌ | Get system logs | Admin |
| `POST` | `/api/admin/backup` | ❌ | Create system backup | Admin |
| `POST` | `/api/admin/restore` | ❌ | Restore from backup | Admin |

### Missing Admin Endpoints
- ❌ `GET /api/admin/stats` - System statistics
- ❌ `GET /api/admin/services` - Service status
- ❌ `POST /api/admin/services/restart` - Restart services
- ❌ `GET /api/admin/security` - Security audit log
- ❌ `POST /api/admin/maintenance` - Maintenance mode

---

## 🌐 Webhooks & Integrations

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `POST` | `/api/webhooks/alerts` | ❌ | Receive alert webhooks | Webhook Key |
| `POST` | `/api/webhooks/devices` | ❌ | Device status webhooks | Webhook Key |
| `GET` | `/api/webhooks` | ❌ | List configured webhooks | Yes |
| `POST` | `/api/webhooks` | ❌ | Create webhook | Yes |
| `DELETE` | `/api/webhooks/[id]` | ❌ | Delete webhook | Yes |

### Missing Integration Endpoints
- ❌ `GET /api/integrations/tailscale` - Tailscale status
- ❌ `POST /api/integrations/tailscale/sync` - Sync Tailscale devices
- ❌ `GET /api/integrations/grafana` - Grafana connection status
- ❌ `GET /api/integrations/influxdb` - InfluxDB connection status

---

## 🔗 WebSocket Endpoints

| Endpoint | Status | Description | Auth Required |
|----------|---------|-------------|---------------|
| `/api/ws` | ❌ | Main WebSocket connection | Yes |
| `/api/devices/[id]/terminal` | 🔧 | SSH terminal WebSocket | Yes |
| `/api/devices/[id]/logs` | ❌ | Real-time log streaming | Yes |

---

## 📈 Search & Filtering

### Global Search

| Method | Endpoint | Status | Description | Auth Required |
|--------|----------|---------|-------------|---------------|
| `GET` | `/api/search` | ❌ | Global search | Yes |
| `GET` | `/api/search/devices` | ❌ | Search devices | Yes |
| `GET` | `/api/search/alerts` | ❌ | Search alerts | Yes |
| `GET` | `/api/search/logs` | ❌ | Search logs | Yes |

---

## 🚨 Priority Implementation List

### High Priority (Core Functionality)
1. ❌ `POST /api/devices/register` - Fix device registration
2. ❌ `GET /api/alerts` - Alert management
3. ❌ `GET /api/devices/[id]/logs` - Device log viewing
4. ❌ `GET /api/admin/users` - User management

### Medium Priority (Enhanced Features)
1. ❌ `GET /api/metrics` - System metrics
2. ❌ `POST /api/webhooks/alerts` - Alert notifications
3. ❌ `GET /api/devices/[id]/files` - File management
4. ❌ `POST /api/admin/backup` - Backup functionality

### Low Priority (Nice to Have)
1. ❌ `GET /api/search` - Global search
2. ❌ `GET /api/integrations/*` - Integration status
3. ❌ `POST /api/devices/[id]/files/upload` - File upload
4. ❌ `GET /api/admin/security` - Security audit

---

## 🔧 Testing Commands

```bash
# Test implemented endpoints
curl -f http://localhost:3001/api/health
curl -H "Authorization: Bearer $JWT_TOKEN" http://localhost:3001/api/devices
curl -H "X-API-Key: $DEVICE_API_KEY" -X POST http://localhost:3001/api/devices

# Test authentication
curl -X POST -H "Content-Type: application/json" \
  -d '{"email":"admin@iotpilot.local","password":"admin"}' \
  http://localhost:3001/api/auth/login

# Test device heartbeat
curl -H "X-API-Key: $DEVICE_API_KEY" -X POST \
  -H "Content-Type: application/json" \
  -d '{"device_id":"test","hostname":"test"}' \
  http://localhost:3001/api/heartbeat
```

---

## 📝 Notes

- **Auth Required**: Endpoints marked "Yes" need JWT token in Authorization header
- **API Key**: Device endpoints need X-API-Key header or Authorization: ApiKey header
- **Admin**: Requires user with ADMIN role
- **Webhook Key**: Requires webhook secret validation

### Environment-Specific URLs
- **Local Dev**: `http://localhost:3001/api/*`
- **Local SSL**: `https://iotpilotserver.test:9443/api/*`
- **Production**: `https://yourdomain.com/api/*`

---

*Last Updated: June 9, 2025*