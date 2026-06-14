// ─── Navigation argument types ───────────────────────────────────────────────

class EventDetailArgs {
  final String eventId;
  const EventDetailArgs({required this.eventId});
}

class CreateEventArgs {
  final String? date;
  const CreateEventArgs({this.date});
}

class ServiceDetailArgs {
  final String serviceId;
  const ServiceDetailArgs({required this.serviceId});
}

class DemarcheDetailArgs {
  final String demarcheId;
  const DemarcheDetailArgs({required this.demarcheId});
}

class UserDemarcheArgs {
  final String userDemarcheId;
  const UserDemarcheArgs({required this.userDemarcheId});
}

class NoteDetailArgs {
  final String noteId;
  const NoteDetailArgs({required this.noteId});
}