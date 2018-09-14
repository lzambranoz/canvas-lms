#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative '../common'
require_relative 'pages/new_user_search_page'
require_relative 'pages/new_user_edit_modal_page.rb'
require_relative 'pages/edit_existing_user_modal_page.rb'
require_relative 'pages/masquerade_page.rb'
require_relative '../conversations/conversations_new_message_modal_page.rb'

describe "new account user search" do
  include_context "in-process server selenium tests"
  include NewUserSearchPage
  include NewUserEditModalPage
  include MasqueradePage
  include ConversationsNewMessageModalPage
  include EditExistingUserModalPage

  before :once do
    @account = Account.default
    account_admin_user(:account => @account, :active_all => true)
  end

  before do
    user_session(@user)
  end

  def get_rows
    ff('[data-automation="users list"] tr')
  end

  def wait_for_loading_to_disappear
    expect(f('[data-automation="users list"]')).not_to contain_css('tr:nth-child(2)')
  end

  describe "with default page visit" do
    before do
      @user.update_attribute(:name, "Test User")
      visit_users(@account)
    end

    it "should bring up user page when clicking name", priority: "1", test_id: 3399648 do
      click_user_link(@user.name)
      expect(f("#content h2")).to include_text @user.name
    end

    it "should open the edit user modal when clicking the edit user icon" do
      click_edit_button(@user.name)
      expect(edit_full_name_input.attribute('value')).to eq(@user.name)
    end

    it "should open the act as page when clicking the masquerade button", priority: "1", test_id: 3453424 do
      click_masquerade_button(@user.name)
      expect(act_as_label).to include_text @user.name
    end

    it "should open the conversation page when clicking the send message button", priority: "1", test_id: 3453435 do
      click_message_button(@user.name)
      expect(message_recipient_input).to include_text @user.name
    end

    it "should search but not find bogus user", priority: "1", test_id: 3399649 do
      enter_search('jtsdumbthing')
      expect(f('#content h2')).to include_text('No users found')
      expect(results_body).not_to contain_css(results_row)
    end

    it "should link to the user group page" do
      click_people_more_options
      click_view_user_groups_option
      expect(driver.current_url).to include("/accounts/#{@account.id}/groups")
    end

    it "should link to the user avatar page" do
      click_people_more_options
      click_manage_profile_pictures_option
      expect(driver.current_url).to include("/accounts/#{@account.id}/avatars")
    end

    it "should search by name" do
      user_with_pseudonym(:account => @account, :name => "diffrient user")
      refresh_page
      user_search_box.send_keys("Test")
      wait_for_loading_to_disappear
      expect(results_rows.count).to eq 1
      expect(results_rows.first).to include_text("Test")
    end
  end

  describe "with no default visit" do
    before do
      @sub_account = Account.create!(name: "sub", parent_account: @account)
    end

    it "should not show the people tab without permission" do
      @account.role_overrides.create! :role => admin_role, :permission => 'read_roster', :enabled => false
      visit_users(@account)
      expect(left_navigation).not_to include_text("People")
    end

    it "should show the create users button user has permission on the root_account" do
      visit_subaccount(@sub_account)
      expect(results_body).to contain_jqcss(add_user_button_jqcss)
    end

    it "should not show the create users button for non-root accounts" do
      account_admin_user(account: @sub_account, active_all: true)
      user_session(@admin)
      visit_subaccount(@sub_account)
      expect(results_body).not_to contain_jqcss(add_user_button_jqcss)
    end

    it "should paginate" do
      ('A'..'Z').each do |letter|
        user_with_pseudonym(:account => @account, :name => "Test User #{letter}")
      end
      visit_users(@account)

      expect(get_rows.count).to eq 15
      expect(get_rows.first).to include_text("Test User A")
      expect(all_results_users).to_not include_text("Test User O")
      expect(results_body).not_to contain_jqcss(page_previous_jqcss)

      click_page_number_button("2")
      wait_for_ajaximations

      expect(get_rows.count).to eq 12
      expect(get_rows.first).to include_text("Test User O")
      expect(get_rows.last).to include_text("Test User Z")
      expect(all_results_users).not_to include_text("Test User A")
    end

    it "should be able to toggle between 'People' and 'Courses' tabs" do
      user_with_pseudonym(:account => @account, :name => "Test User")
      course_factory(:account => @account, :course_name => "Test Course")

      visit_courses(@account)
      2.times do
        expect(breadcrumbs).not_to include_text("People")
        expect(breadcrumbs).to include_text("Courses")
        expect(all_results_courses).to include_text("Test Course")

        click_left_nav_users
        expect(driver.current_url).to include("/accounts/#{@account.id}/users")
        expect(breadcrumbs).to include_text("People")
        expect(breadcrumbs).not_to include_text("Courses")
        expect(all_results_users).to include_text("Test User")

        click_left_nav_courses
      end
    end

    it "should be able to create users" do
      name = 'Test User'
      email = 'someemail@example.com'
      visit_users(@account)

      click_add_user
      expect(modal_object).to be_displayed

      set_value(full_name_input, name)
      expect(sortable_name_input.attribute('value')).to eq "User, Test"

      set_value(email_input, email)

      click_modal_submit

      new_pseudonym = Pseudonym.where(:unique_id => email).first
      expect(new_pseudonym.user.name).to eq name

      # should refresh the users list
      expect(all_results_users).to include_text(name)
      expect(get_rows.count).to eq 2 # the first user is the admin
      expect(user_row(name)).to include_text(email)

      # should clear out the inputs
      click_add_user
      expect(full_name_input.attribute('value')).to eq('')
    end

    it "should be able to create users with confirmation disabled", priority: "1", test_id: 3399311 do
      name = 'Confirmation Disabled'
      email = 'someemail@example.com'
      visit_users(@account)

      click_add_user

      set_value(full_name_input, name)
      set_value(email_input, email)

      click_email_creation_check
      click_modal_submit

      new_pseudonym = Pseudonym.where(:unique_id => email).first
      expect(new_pseudonym.user.name).to eq name
    end
  end
end
