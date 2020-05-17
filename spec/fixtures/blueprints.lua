local ssl_fixtures = require "spec.fixtures.ssl"
local utils = require "kong.tools.utils"

local deep_merge = utils.deep_merge
local fmt = string.format


local Blueprint   = {}
Blueprint.__index = Blueprint


function Blueprint:build(overrides)
  overrides = overrides or {}
  return deep_merge(self.build_function(overrides), overrides)
end


function Blueprint:insert(overrides, options)
  local entity, err = self.dao:insert(self:build(overrides), options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:remove(overrides, options)
  local entity, err = self.dao:remove({ id = overrides.id }, options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:update(id, overrides, options)
  local entity, err = self.dao:update(id, overrides, options)
  if err then
    error(err, 2)
  end
  return entity
end


function Blueprint:insert_n(n, overrides, options)
  local res = {}
  for i=1,n do
    res[i] = self:insert(overrides, options)
  end
  return res
end


local Blueprints  = {}
Blueprints.__index = Blueprints


function Blueprints:new_blueprint(dao, build_function)
  return setmetatable({
    dao = dao,
    build_function = build_function,
  }, Blueprint)
end


local Sequence = {}
Sequence.__index = Sequence


function Sequence:next()
  self.count = self.count + 1
  return fmt(self.sequence_string, self.count)
end


local function new_sequence(sequence_string)
  return setmetatable({
    count           = 0,
    sequence_string = sequence_string,
  }, Sequence)
end


local _M = {}


function _M.new(db)
  local sni_seq = new_sequence("server-name-%d")
  Blueprints.snis = Blueprints:new_blueprint(db.snis, function(overrides)
    return {
      name        = overrides.name or sni_seq:next(),
      certificate = overrides.certificate or Blueprints.certificates:insert(),
    }
  end)

  Blueprints.certificates = Blueprints:new_blueprint(db.certificates, function()
    return {
      cert = ssl_fixtures.cert,
      key  = ssl_fixtures.key,
    }
  end)

  Blueprints.ca_certificates = Blueprints:new_blueprint(db.ca_certificates, function()
    return {
      cert = ssl_fixtures.cert_ca,
    }
  end)

  local upstream_name_seq = new_sequence("upstream-%d")
  Blueprints.upstreams = Blueprints:new_blueprint(db.upstreams, function(overrides)
    local slots = overrides.slots or 100
    local name = overrides.name or upstream_name_seq:next()
    local host_header = overrides.host_header or nil

    return {
      name      = name,
      slots     = slots,
      host_header = host_header,
    }
  end)

  local consumer_custom_id_seq = new_sequence("consumer-id-%d")
  local consumer_username_seq = new_sequence("consumer-username-%d")
  Blueprints.consumers = Blueprints:new_blueprint(db.consumers, function()
    return {
      custom_id = consumer_custom_id_seq:next(),
      username  = consumer_username_seq:next(),
    }
  end)

  Blueprints.targets = Blueprints:new_blueprint(db.targets, function(overrides)
    return {
      weight = 10,
      upstream = overrides.upstream or Blueprints.upstreams:insert(),
    }
  end)

  Blueprints.plugins = Blueprints:new_blueprint(db.plugins, function()
    return {}
  end)

  Blueprints.routes = Blueprints:new_blueprint(db.routes, function(overrides)
    return {
      service = overrides.service or Blueprints.services:insert(),
    }
  end)

  Blueprints.services = Blueprints:new_blueprint(db.services, function()
    return {
      protocol = "http",
      host = "127.0.0.1",
      port = 15555,
    }
  end)

  local named_service_name_seq = new_sequence("service-name-%d")
  local named_service_host_seq = new_sequence("service-host-%d.test")
  Blueprints.named_services = Blueprints:new_blueprint(db.services, function()
    return {
      protocol = "http",
      name = named_service_name_seq:next(),
      host = named_service_host_seq:next(),
      port = 15555,
    }
  end)

  local named_route_name_seq = new_sequence("route-name-%d")
  local named_route_host_seq = new_sequence("route-host-%d.test")
  Blueprints.named_routes = Blueprints:new_blueprint(db.routes, function(overrides)
    return {
      name = named_route_name_seq:next(),
      hosts = { named_route_host_seq:next() },
      service = overrides.service or Blueprints.services:insert(),
    }
  end)

  Blueprints.acl_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "acl",
      config = {},
    }
  end)

  local acl_group_seq = new_sequence("acl-group-%d")
  Blueprints.acls = Blueprints:new_blueprint(db.acls, function()
    return {
      group = acl_group_seq:next(),
    }
  end)

  Blueprints.cors_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "cors",
      config = {
        origins         = { "example.com" },
        methods         = { "GET" },
        headers         = { "origin", "type", "accepts"},
        exposed_headers = { "x-auth-token" },
        max_age         = 23,
        credentials     = true,
      }
    }
  end)

  Blueprints.loggly_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "loggly",
      config = {}, -- all fields have default values already
    }
  end)

  Blueprints.tcp_log_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "tcp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  Blueprints.udp_log_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = 35001,
      },
    }
  end)

  Blueprints.jwt_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "jwt",
      config = {},
    }
  end)

  local jwt_key_seq = new_sequence("jwt-key-%d")
  Blueprints.jwt_secrets = Blueprints:new_blueprint(db.jwt_secrets, function()
    return {
      key       = jwt_key_seq:next(),
      secret    = "secret",
    }
  end)

  Blueprints.oauth2_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "oauth2",
      config = {
        scopes                    = { "email", "profile" },
        enable_authorization_code = true,
        mandatory_scope           = true,
        provision_key             = "provision123",
        token_expiration          = 5,
        enable_implicit_grant     = true,
      }
    }
  end)

  Blueprints.oauth2_credentials = Blueprints:new_blueprint(db.oauth2_credentials, function()
    return {
      name          = "oauth2 credential",
      client_secret = "secret",
    }
  end)

  local oauth_code_seq = new_sequence("oauth-code-%d")
  Blueprints.oauth2_authorization_codes = Blueprints:new_blueprint(db.oauth2_authorization_codes, function()
    return {
      code  = oauth_code_seq:next(),
      scope = "default",
    }
  end)

  Blueprints.oauth2_tokens = Blueprints:new_blueprint(db.oauth2_tokens, function()
    return {
      token_type = "bearer",
      expiBlueprints_in = 1000000000,
      scope      = "default",
    }
  end)

  Blueprints.key_auth_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "key-auth",
      config = {},
    }
  end)

  local keyauth_key_seq = new_sequence("keyauth-key-%d")
  Blueprints.keyauth_credentials = Blueprints:new_blueprint(db.keyauth_credentials, function()
    return {
      key = keyauth_key_seq:next(),
    }
  end)

  Blueprints.basicauth_credentials = Blueprints:new_blueprint(db.basicauth_credentials, function()
    return {}
  end)

  Blueprints.hmac_auth_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "hmac-auth",
      config = {},
    }
  end)

  local hmac_username_seq = new_sequence("hmac-username-%d")
  Blueprints.hmacauth_credentials = Blueprints:new_blueprint(db.hmacauth_credentials, function()
    return {
      username = hmac_username_seq:next(),
      secret   = "secret",
    }
  end)

  Blueprints.rate_limiting_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "rate-limiting",
      config = {},
    }
  end)

  Blueprints.Blueprintsponse_ratelimiting_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "Blueprintsponse-ratelimiting",
      config = {},
    }
  end)

  Blueprints.datadog_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "datadog",
      config = {},
    }
  end)

  Blueprints.statsd_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "statsd",
      config = {},
    }
  end)

  Blueprints.rewriter_plugins = Blueprints:new_blueprint(db.plugins, function()
    return {
      name   = "rewriter",
      config = {},
    }
  end)


  return Blueprints
end

return _M
