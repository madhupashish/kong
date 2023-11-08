local _M = {}


local atc = require("kong.router.atc")
local gen_for_field = atc.gen_for_field


local OP_EQUAL    = "=="


local LOGICAL_AND = atc.LOGICAL_AND


-- map to normal protocol
local PROTOCOLS_OVERRIDE = {
  tls_passthrough = "tcp",
  grpc            = "http",
  grpcs           = "https",
}


-- net.port => net.dst.port
local function verify_expression(exp)
  if not exp then
    return nil
  end

  if exp:find("net.port", 1, true) then
    ngx.log(ngx.WARN, "The field 'net.port' of expression is deprecated, " ..
                      "please use 'net.dst.port' instead.")

    return exp:gsub("net%.port", "net.dst.port")
  end

  return exp
end
_M.verify_expression = verify_expression


local function get_exp_and_priority(route)
  local exp = verify_expression(route.expression)
  if not exp then
    ngx.log(ngx.ERR, "expecting an expression route while it's not (probably a traditional route). ",
                     "Likely it's a misconfiguration. Please check the 'router_flavor' config in kong.conf")
    return
  end

  local protocols = route.protocols

  -- give the chance for http redirection (301/302/307/308/426)
  -- and allow tcp works with tls
  if protocols and #protocols == 1 and
    (protocols[1] == "https" or
     protocols[1] == "tls" or
     protocols[1] == "tls_passthrough")
  then
    return exp, route.priority
  end

  local gen = gen_for_field("net.protocol", OP_EQUAL, protocols,
                            function(_, p)
                              return PROTOCOLS_OVERRIDE[p] or p
                            end)
  if gen then
    exp = exp .. LOGICAL_AND .. gen
  end

  return exp, route.priority
end


function _M.new(routes, cache, cache_neg, old_router)
  return atc.new(routes, cache, cache_neg, old_router, get_exp_and_priority)
end


-- for unit-testing purposes only
_M._set_ngx = atc._set_ngx


return _M
