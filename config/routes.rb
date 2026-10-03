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
  resource :account, only: [ :update ], controller: "accounts"
  resources :agent_tokens, only: [ :create, :destroy ]
  resources :friendships, only: [ :create, :destroy ]
  resources :blurbs, only: [ :create, :update, :destroy ] do
    member { patch :move }
  end

  # The picture is a singleton on the account, like the profile page itself.
  patch "profile/picture", to: "profiles#update_picture", as: :profile_picture
  delete "profile/picture", to: "profiles#destroy_picture"

  # Comments are left on a page, so they are nested under the username a visitor
  # is looking at; removal is by comment id, which the comment knows its page from.
  post "profiles/:username/comments", to: "comments#create", as: :profile_comments
  delete "comments/:id", to: "comments#destroy", as: :comment

  resources :profiles, only: [ :show ], param: :username

  root "pages#home"
end
