import 'package:flutter/material.dart';
import 'package:flutter_cached/flutter_cached.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:schulcloud/app/app.dart';
import 'package:schulcloud/app/chip.dart';
import 'package:schulcloud/course/course.dart';
import 'package:schulcloud/file/file.dart';
import 'package:schulcloud/file/widgets/file_tile.dart';

import '../bloc.dart';
import '../data.dart';
import 'edit_submittion_screen.dart';
import 'grade_indicator.dart';

class AssignmentDetailsScreen extends StatefulWidget {
  const AssignmentDetailsScreen({Key key, @required this.assignment})
      : assert(assignment != null),
        super(key: key);

  final Assignment assignment;

  @override
  _AssignmentDetailsScreenState createState() =>
      _AssignmentDetailsScreenState();
}

class _AssignmentDetailsScreenState extends State<AssignmentDetailsScreen>
    with TickerProviderStateMixin {
  Assignment get assignment => widget.assignment;

  @override
  Widget build(BuildContext context) {
    return CachedRawBuilder<User>(
      controller: services.get<UserFetcherService>().fetchCurrentUser(),
      builder: (context, update) {
        final user = update.data;
        final showSubmissionTab =
            assignment.isPrivate || user?.isTeacher == false;
        final showFeedbackTab = assignment.isPublic && user?.isTeacher == false;

        final tabs = [
          Tab(text: 'Details'),
          if (showSubmissionTab) Tab(text: 'Submission'),
          if (showFeedbackTab) Tab(text: 'Feedback'),
        ];
        final controller = TabController(length: tabs.length, vsync: this);

        return FancyTabbedScaffold(
          controller: controller,
          appBarBuilder: (innerBoxIsScrolled) => FancyAppBar(
            title: Text(assignment.name),
            forceElevated: innerBoxIsScrolled,
            bottom: TabBar(
              controller: controller,
              tabs: tabs,
            ),
          ),
          tabs: [
            _DetailsTab(assignment: assignment),
            if (showSubmissionTab) _SubmissionTab(assignment: assignment),
            if (showFeedbackTab) _FeedbackTab(assignment: assignment),
          ],
        );
      },
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({Key key, @required this.assignment})
      : assert(assignment != null),
        super(key: key);

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final textTheme = context.textTheme;

    var datesText = 'Available: ${assignment.availableAt.longDateTimeString}';
    if (assignment.dueAt != null) {
      datesText += '\nDue: ${assignment.dueAt.longDateTimeString}';
    }

    return TabContent(
      pageStorageKey: PageStorageKey<String>('details'),
      omitHorizontalPadding: true,
      child: SliverList(
        delegate: SliverChildListDelegate.fixed([
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              datesText,
              style: textTheme.body1,
              textAlign: TextAlign.end,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Html(
              data: assignment.description,
              onLinkTap: tryLaunchingUrl,
            ),
          ),
          ..._buildFileSection(context, assignment.fileIds, assignment.id),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ChipGroup(
              children: _buildChips(context),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _buildChips(BuildContext context) {
    final s = context.s;

    return <Widget>[
      if (assignment.courseId != null)
        CachedRawBuilder<Course>(
          controller: services
              .get<AssignmentBloc>()
              .fetchCourseOfAssignment(assignment),
          builder: (_, update) {
            final course = update.data;

            return CourseChip(course);
          },
        ),
      if (assignment.isOverDue)
        ActionChip(
          avatar: Icon(
            Icons.flag,
            color: context.theme.errorColor,
          ),
          label: Text(s.assignment_assignment_overdue),
          onPressed: () {},
        ),
      if (assignment.isArchived)
        Chip(
          avatar: Icon(Icons.archive),
          label: Text(s.assignment_assignment_isArchived),
        ),
      if (assignment.isPrivate)
        Chip(
          avatar: Icon(Icons.lock),
          label: Text(s.assignment_assignment_isPrivate),
        ),
      if (assignment.hasPublicSubmissions)
        Chip(
          avatar: Icon(Icons.public),
          label: Text('Public submissions'),
        ),
    ];
  }
}

class _SubmissionTab extends StatelessWidget {
  const _SubmissionTab({Key key, @required this.assignment})
      : assert(assignment != null),
        super(key: key);

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return CachedRawBuilder<Submission>(
      controller: services.get<SubmissionBloc>().fetchMySubmission(assignment),
      builder: (_, update) {
        if (update.hasError) {
          return ErrorScreen(update.error, update.stackTrace);
        }

        // TODO(marcelgarus): use Maybe<Submission> to differentiate between loading and no submission when updating flutter_cached
        final submission = update.data;
        return Stack(
          children: <Widget>[
            TabContent(
              pageStorageKey: PageStorageKey<String>('submission'),
              omitHorizontalPadding: true,
              child: _buildContent(context, submission),
            ),
            _buildOverlay(submission),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, Submission submission) {
    Widget child = submission == null
        ? Text('You have not submitted anything yet.')
        : Html(
            data: submission.comment,
            onLinkTap: tryLaunchingUrl,
          );
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
        if (submission != null)
          ..._buildFileSection(context, submission.fileIds, submission.id),
        if (!assignment.isOverDue) FabSpacer(),
      ]),
    );
  }

  Widget _buildOverlay(Submission submission) {
    if (assignment.isOverDue) {
      return SizedBox.shrink();
    }

    return CachedRawBuilder<User>(
      controller: services.get<UserFetcherService>().fetchCurrentUser(),
      builder: (context, update) {
        if (update.hasError) {
          return ErrorScreen(update.error, update.stackTrace);
        }
        if (update.data == null) {
          return SizedBox.shrink();
        }
        final user = update.data;

        String labelText;
        if (submission == null &&
            user.hasPermission(Permission.submissionsCreate)) {
          labelText = 'Create submission';
        } else if (submission != null &&
            user.hasPermission(Permission.submissionsEdit)) {
          labelText = 'Edit submission';
        }
        if (labelText == null) {
          return SizedBox.shrink();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton.extended(
              onPressed: () => context.navigator.push(MaterialPageRoute(
                builder: (_) => EditSubmissionScreen(
                  assignment: assignment,
                  submission: submission,
                ),
              )),
              label: Text(labelText),
              icon: Icon(Icons.edit),
            ),
          ),
        );
      },
    );
  }
}

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({Key key, @required this.assignment})
      : assert(assignment != null),
        super(key: key);

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return CachedRawBuilder<Submission>(
      controller: services.get<SubmissionBloc>().fetchMySubmission(assignment),
      builder: (_, update) {
        if (!update.hasData) {
          return update.hasError
              ? ErrorScreen(update.error, update.stackTrace)
              : Center(child: CircularProgressIndicator());
        }

        final submission = update.data;
        return TabContent(
          pageStorageKey: PageStorageKey<String>('feedback'),
          omitHorizontalPadding: true,
          child: SliverList(
            delegate: SliverChildListDelegate.fixed([
              if (submission.grade != null) ...[
                ListTile(
                  leading: GradeIndicator(grade: submission.grade),
                  title: Text('You solved ${submission.grade} % correctly.'),
                ),
                SizedBox(height: 8),
              ],
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: submission.gradeComment != null
                    ? Html(
                        data: submission.gradeComment,
                        onLinkTap: tryLaunchingUrl,
                      )
                    : Text('No feedback text available.'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

List<Widget> _buildFileSection(
  BuildContext context,
  List<Id<File>> fileIds,
  Id<dynamic> parentId,
) {
  return [
    if (fileIds.isNotEmpty) ...[
      SizedBox(height: 8),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Files',
          style: context.textTheme.caption,
        ),
      ),
    ],
    for (final fileId in fileIds)
      CachedRawBuilder<File>(
        controller: services.get<FileBloc>().fetchFile(fileId, parentId),
        builder: (context, update) {
          if (!update.hasData) {
            return ListTile(
              leading:
                  update.hasError == null ? CircularProgressIndicator() : null,
              title:
                  Text(update.error?.toString() ?? context.s.general_loading),
            );
          }

          final file = update.data;
          return FileTile(
            file: file,
            onOpen: (file) => FileBrowser.downloadFile(context, file),
          );
        },
      ),
  ];
}
