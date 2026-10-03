# frozen_string_literal: true

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The agent contract, in the two forms it is read in: a page for the owner, raw
  # markdown for the coding agent they hand a token to. The markdown path is
  # declared with format parsing off, so `/agents.md` is that literal path rather
  # than the `/agents` page with a `.md` format it cannot render.
  get "agents.md", to: "pages#agents_markdown", as: :agents_markdown, format: false
  get "agents", to: "pages#agents", as: :agents

  namespace :api do
    namespace :v1 do
      resource :profile, only: [ :show, :update ], controller: "profiles"
    end
  end

  resource :registration, only: [ :new, :create ]
  resource :session, only: [ :new, :create, :destroy ]
  resource :studio, only: [ :show, :update ], controller: "studio"
  resources :agent_tokens, only: [ :create, :destroy ]
  resources :profiles, only: [ :show ], param: :username

  root "pages#home"
end
