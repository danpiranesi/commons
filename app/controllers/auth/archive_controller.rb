module Auth
  class ArchiveController < ApplicationController
    skip_before_action :authenticate_user!

    def verify
      if logged_in? && DiscourseSso.new.access_allowed?(session[:groups] || [])
        head :ok
      elsif logged_in?
        head :forbidden
      else
        redirect_to "#{Rails.application.config.booking_base_url}/login" \
          "?return=#{CGI.escape(forwarded_url)}", allow_other_host: true
      end
    end

    private

    def forwarded_url
      proto = request.headers["X-Forwarded-Proto"].presence || "https"
      host  = request.headers["X-Forwarded-Host"].presence  || "archive.example.org"
      uri   = request.headers["X-Forwarded-Uri"].presence   || "/"
      "#{proto}://#{host}#{uri}"
    end
  end
end
