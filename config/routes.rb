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
      # The rice, for a client that manages the whole space rather than only the markup.
      resource :showcase, only: [ :show, :update ], controller: "showcases"
      # Everything else that lives on a page: links, demos, hardware, friends, blurbs.
      resource :page, only: [ :show, :update ], controller: "page"
      # The pictures themselves: a folder has assets/, and a folder whose pictures cannot
      # be pushed is not a folder that holds the page.
      resources :images, only: [ :create, :destroy ]
      # The whole order at once: a folder holds one order, and sending it as N moves would
      # be N requests to say one thing.
      patch "images/order", to: "images#order"
      # What other people said about a page: the score of your own, and your opinion of
      # somebody else's. The one fact on a page its owner does not write.
      resource :ratings, only: :show, controller: "ratings"
      put "ratings/:username", to: "ratings#update", as: :rate_page
    end
  end

  resource :registration, only: [ :new, :create ]
  resource :session, only: [ :new, :create, :destroy ]
  resource :studio, only: [ :show, :update ], controller: "studio"
  patch "studio/song", to: "studio#update_song", as: :update_song_studio

  # The showcase: the rice. Edited as one thing, because it is one thing.
  resource :showcase, only: [ :edit, :update ], controller: "showcases"
  post "showcase/shots", to: "showcases#add_shot", as: :showcase_shots
  delete "showcase/shots/:id", to: "showcases#remove_shot", as: :showcase_shot
  patch "showcase/shots/:id/move", to: "showcases#move_shot", as: :move_showcase_shot
  resource :account, only: [ :update, :destroy ], controller: "accounts"

  # Liking a page. One opinion per person per page — see RatingsController.
  post "profiles/:username/rate", to: "ratings#create", as: :rate_profile

  # The local preview: draws a folder from disk with the site's own renderer, so a person
  # editing files sees the page the site will make of them. Local only — nothing is stored.
  get "preview/:folder", to: "preview#show", as: :preview, constraints: { folder: /[^\/]+/ }

  resources :agent_tokens, only: [ :create, :destroy ]
  resources :friendships, only: [ :create, :destroy ] do
    member { patch :move }
  end

  # The videos and streams on a page. Links only — the video stays where it is hosted.
  resources :stream_links, only: [ :create, :destroy ]

  # The demoscene demos on a page: its own category, with its own facts.
  resources :demos, only: [ :create, :update, :destroy ]

  # The hardware on a page: a build, its photos, and what is in it.
  resources :builds, only: [ :create, :update, :destroy ] do
    member do
      post :add_photo
      delete "photos/:photo_id", action: :remove_photo, as: :remove_photo
    end
  end
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

  # Taking somebody's layout onto your own page, from their page.
  post "profiles/:username/copy_layout", to: "profiles#copy_layout", as: :copy_layout_profile

  # Favorites and blocks — the MySpace "Contacting" section.
  post "profiles/:username/favorite", to: "profiles#favorite", as: :favorite_profile
  delete "profiles/:username/favorite", to: "profiles#unfavorite"
  post "profiles/:username/block", to: "profiles#block", as: :block_profile
  delete "profiles/:username/block", to: "profiles#unblock"

  resources :profiles, only: [ :show ], param: :username

  # The published layouts. `apply` is a POST because it changes a page.
  resources :layouts, only: [ :index, :show ] do
    member { post :apply }
  end

  root "pages#home"
end
