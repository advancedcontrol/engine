
function(doc, meta) {
    if(doc.type == "sys") {
        emit(meta.id, null);
    }
}
