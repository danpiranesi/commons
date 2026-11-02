Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  get "login", to: "sessions#new", as: :login
  get "auth/callback", to: "sessions#callback", as: :sso_callback
  delete "logout", to: "sessions#destroy", as: :logout

  # Admin
  namespace :admin do
    get   "design", to: "design#show",   as: :design
    patch "design", to: "design#update"
    # Batch QR label printing (multi-select on the resources list)
    resource :label_sheet, only: [:new, :create]

    # Billing: rates per category, and the groups a booking can be made for
    resources :billing_categories, only: [:index] do
      patch :update_all, on: :collection
    end
    resources :billing_groups, except: [:show] do
      member do
        post   :add_member
        delete :remove_member
      end
    end
    get   "rules",  to: "rules#show",    as: :rules
    patch "rules",  to: "rules#update"
    get   "homepage_header", to: "site_settings#edit",   as: :homepage_header
    patch "homepage_header", to: "site_settings#update"
    resources :resource_types, only: [:index, :new, :create, :edit, :update]
    resources :bookings, only: [:edit, :update, :destroy]
    resources :users, only: [:index, :edit, :update] do
      collection { get :search }
    end
    resource :monthly_overview, only: [:show], controller: "monthly_overview" do
      patch :update_mileage
      post  :close_month
      get   :export_csv
      get   :export_summary
    end
    resources :resources do
      member do
        patch :toggle_status
        patch :recharge
        get   :regenerate_qr_confirm
        post  :regenerate_qr
        get   :label
      end
    end
  end

  # Bookings
  resources :bookings, only: [:new, :create, :show, :edit, :update, :destroy] do
    member do
      get :price_preview
      patch :cancel
      patch :complete
      patch :adjust_end
    end
  end

  # Public resource detail
  resources :resources, only: [:show, :update]

  # Public wall-mounted weekly schedule (no login to read)
  get "/schedule", to: "schedule#show", as: :schedule

  # On-site kiosk end-reservation flow (last-4-of-phone lookup)
  get "/kiosk", to: "kiosk#show", as: :kiosk

  # Vehicle QR entry point (public — the token is the credential)
  get "/v/:token", to: "vehicle_scans#show", as: :vehicle_scan
  # Shared end/extend targets for QR, kiosk and the active-booking panel
  resource :reservation_check_in,   only: [:create]
  resource :reservation_completion, only: [:create]
  resource :reservation_extension,  only: [:create]

  # Mobile booking wizard
  get "wizard/times",   to: "wizard#times",   as: :wizard_times
  get "wizard/results", to: "wizard#results", as: :wizard_results

  # Test-only auth bypass
  if Rails.env.test?
    get "test/sign_in/:user_id", to: "test_sessions#create"
  end

  # Settings
  resource :settings, only: [:edit, :update]

  # Admin "see it as a member" switch (and the way back). Outside /admin on
  # purpose: while previewing, admin routes refuse the user.
  resource :member_preview, only: [:create, :destroy]

  # A member's own booking history (month by month, with CSV export)
  resource :usage, only: [:show], controller: "usage"

  # Calendar
  resource :calendar, only: [:show], controller: "calendar"

  root "calendar#show"
end
