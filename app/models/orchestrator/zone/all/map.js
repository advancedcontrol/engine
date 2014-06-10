
function(doc) {
    if(doc.type == "zone") {
        emit(doc.id, null);
    }
}
