
function(doc) {
    if(doc.type == "mod" && doc.dependency_id != null) {
        emit(doc.dependency_id, null);
    }
}
