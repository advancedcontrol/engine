
function(doc) {
    if(doc.type == "mod" && doc.control_system_id != null) {
        emit(doc.control_system_id, null);
    }
}
