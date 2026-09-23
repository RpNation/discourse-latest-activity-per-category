# frozen_string_literal: true

DiscourseCategoryLatestTopics::Engine.routes.draw do
  get "/examples" => "examples#index"
  # define routes here
end

Discourse::Application.routes.draw { mount ::DiscourseCategoryLatestTopics::Engine, at: "discourse-category-latest-topics" }
