class DiscourseSso
  class InvalidSignatureError < StandardError; end

  def initialize
    @secret = Rails.application.credentials.dig(:discourse, :sso_secret) || ENV["DISCOURSE_CONNECT_PROVIDER_SECRET"]
    @discourse_url = Rails.application.config.discourse_url
  end

  def login_url(return_url:, nonce:)
    payload = Base64.strict_encode64("nonce=#{nonce}&return_sso_url=#{return_url}")
    sig = sign(payload)
    "#{@discourse_url}/session/sso_provider?sso=#{CGI.escape(payload)}&sig=#{sig}"
  end

  def parse_callback(sso:, sig:)
    raise InvalidSignatureError, "Invalid SSO signature" unless valid_signature?(sso, sig)

    decoded = Base64.decode64(sso)
    params = Rack::Utils.parse_query(decoded)

    {
      nonce: params["nonce"],
      discourse_id: params["external_id"].to_i,
      email: params["email"],
      name: params["name"] || params["username"],
      username: params["username"],
      groups: (params["groups"] || "").split(",").map(&:strip)
    }
  end

  def user_type_from_groups(groups)
    return "resident" if groups.include?("residents")
    return "employee" if groups.include?("employees")
    "resident"
  end

  def admin_from_groups?(groups)
    groups.map(&:downcase).include?("booking-admins")
  end

  def access_allowed?(groups)
    groups.map(&:downcase).exclude?("volunteers")
  end

  private

  def sign(payload)
    OpenSSL::HMAC.hexdigest("SHA256", @secret, payload)
  end

  def valid_signature?(payload, sig)
    expected = sign(payload)
    ActiveSupport::SecurityUtils.secure_compare(expected, sig)
  end
end
