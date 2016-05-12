function(doc) {
    if(doc.type === "user") {
        emit(doc.authority_id, null);
    }
}
