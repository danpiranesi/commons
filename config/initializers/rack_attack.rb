# Cheap defense against brute-forcing the QR token space. The token is
# 43 chars of urlsafe_base64 (~256 bits) so this is belt-and-suspenders, but the
# scan path is public and unauthenticated, so a per-IP throttle is worth having.
Rack::Attack.throttle("scans/ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/v/")
end
