require 'spec_helper'

describe Meeting do
  it {should belong_to :project}
  it {should belong_to :author}
  it {should validate_presence_of :title}
  it {should validate_presence_of :start_time}
  it {pending; should accept_nested_attributes_for :participants} # geht das?

  let(:project) { FactoryGirl.create(:project) }
  let(:user1) { FactoryGirl.create(:user) }
  let(:user2) { FactoryGirl.create(:user) }
  let(:meeting) { FactoryGirl.create(:meeting, :project => project, :author => user1) }
  let(:role) { FactoryGirl.create(:role, :permissions => [:view_meetings]) }

  before(:all) do
    @m = FactoryGirl.build :meeting, :title => "dingens"
  end

  describe "to_s" do
    it {@m.to_s.should == "dingens"}
  end

  describe "start_date" do
    it {@m.start_date.should == Date.tomorrow}
  end

  describe "start_month" do
    it {@m.start_month.should == Date.tomorrow.month}
  end

  describe "start_year" do
    it {@m.start_year.should == Date.tomorrow.year}
  end

  describe "end_time" do
    it {@m.end_time.should == Date.tomorrow + 11.hours}
  end

  describe "time-sorted finder" do
    it {pending}
  end

  describe "Journalized Objects" do
    before(:each) do
      @project ||= FactoryGirl.create(:project_with_trackers)
      @current = FactoryGirl.create(:user, :login => "user1", :mail => "user1@users.com")
      User.stub!(:current).and_return(@current)
    end

    it 'should work with meeting' do
      @meeting ||= FactoryGirl.create(:meeting, :title => "Test", :project => @project, :author => @current)

      initial_journal = @meeting.journals.first
      recreated_journal = @meeting.recreate_initial_journal!
      initial_journal.identical?(recreated_journal).should be true
    end
  end

  describe "all_possible_participants" do
    describe "WITH a user having the view_meetings permission" do
      before do
        project.add_member user1, [role]
        project.save!
      end

      it "should contain the user" do
        meeting.all_possible_participants.should == [user1]
      end
    end

    describe "WITH a user not having the view_meetings permission" do
      let(:role2) { FactoryGirl.create(:role, :permissions => []) }

      before do
        # adding both users so that the author is valid
        project.add_member user1, [role]
        project.add_member user2, [role2]

        project.save!
      end

      it "should not contain the user" do
        meeting.all_possible_participants.include?(user2).should be_false
      end
    end

  end

  describe "participants and author as watchers" do
    before do
      project.add_member user1, [role]
      project.add_member user2, [role]

      project.save!

      meeting.participants.build(:user => user2)
      meeting.save!
    end

    it { meeting.watchers.collect(&:user).should =~ [user1, user2] }
  end

  describe "Copied meetings" do
    before do
      project.add_member user1, [role]
      project.add_member user2, [role]

      project.save!

      meeting.start_time = DateTime.new(2013,3,27,15,35)
      meeting.participants.build(:user => user2)
      meeting.save!
    end

    it "should have the same start_time as the original meeting" do
      copy = meeting.copy({})
      copy.start_time == meeting.start_time
    end

    it "should delete the copied meeting author if no author is given as parameter" do
      copy = meeting.copy({})
      copy.author.nil?
    end

    it "should set the author the provided author if one is given" do
      copy = meeting.copy :author => user2
      copy.author == user2
    end

    it "should clear participant ids and attended flags for all copied attendees" do
      copy = meeting.copy({})
      copy.participants.all { |p| p.id.nil? && !p.attended}
    end
  end
end
